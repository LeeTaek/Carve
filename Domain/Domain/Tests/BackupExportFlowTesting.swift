//
//  BackupExportFlowTesting.swift
//  DomainTest
//
//  필사 백업 내보내기 — 장 사이의 계정 · 세대 변경, 다 쓴 파일의 재검증, 파일 이름, 작업 폴더 정리 (설계 docs/backup-import-design.md §3-1 · §3-2).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 장 사이에 계정이 바뀌었는데 계속 읽어 두 계정의 초안을 한 파일에 섞는 것
/// - 장 사이에 「모든 필사 삭제」 가 있었는데 앞 장(지운 필사)과 뒤 장(빈 저장소)이 섞인 파일을 성공으로 내놓는 것
/// - 다 쓴 파일을 다시 열어 보지 않고 성공으로 내놓는 것, 실패 · 취소 뒤 평문 작업 폴더를 남기는 것
@Suite("백업 내보내기 — 흐름")
struct BackupExportFlowTesting {

    /// 두 장에 행 하나씩.
    private func seedTwoChapters(_ harness: BackupExportHarness) throws {
        try harness.seed([
            BackupExportRowSeed(verse: 1, rowUUID: "GEN1", lineData: BackupExportSample.ink("1"), layoutMetadataData: BackupExportSample.metadata),
            BackupExportRowSeed(
                chapter: BackupExportSample.genesis2, verse: 1, rowUUID: "GEN2",
                lineData: BackupExportSample.ink("2"), layoutMetadataData: BackupExportSample.metadata
            )
        ])
    }

    @Test("장 사이에 계정이 바뀌면 accountChanged 로 멈추고 작업 폴더를 남기지 않는다")
    func accountChangeBetweenChaptersStopsTheExport() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)
        let environment = SwitchableBackupEnvironment(BackupExportSample.confirmed(BackupExportSample.accountA))

        // When: 첫 장을 마친 뒤 다른 계정으로 바뀐다.
        await #expect(throws: BackupExportError.accountChanged) {
            _ = try await harness.exporter(environment).export(password: BackupExportSample.password) { progress in
                if progress.done == 1 { environment.set(BackupExportSample.confirmed(BackupExportSample.accountB)) }
            }
        }

        // Then
        #expect(harness.leftovers().isEmpty)
    }

    @Test("계정은 그대로인데 저장소 소유 근거가 바뀌거나 로그아웃해도 accountChanged 다")
    func ownershipOrSignOutBetweenChaptersStopsTheExport() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)
        var ownerless = BackupExportSample.confirmed(BackupExportSample.accountA)
        ownerless.storeOwnership = nil
        for next in [ownerless, BackupExportSample.signedOut] {
            let environment = SwitchableBackupEnvironment(BackupExportSample.confirmed(BackupExportSample.accountA))

            await #expect(throws: BackupExportError.accountChanged) {
                _ = try await harness.exporter(environment).export(password: BackupExportSample.password) { progress in
                    if progress.done == 1 { environment.set(next) }
                }
            }
        }
        #expect(harness.leftovers().isEmpty)
    }

    @Test("장 사이에 「모든 필사 삭제」 로 저장소 세대가 바뀌면 generationChanged 로 멈춘다")
    func generationChangeBetweenChaptersStopsTheExport() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)
        let database = harness.database

        // When: 첫 장을 마친 뒤 모든 필사를 지운다.
        await #expect(throws: BackupExportError.generationChanged) {
            _ = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
                .export(password: BackupExportSample.password) { progress in
                    if progress.done == 1 { try? await database.eraseAllDrawingRows() }
                }
        }

        // Then
        #expect(harness.leftovers().isEmpty)
    }

    @Test("다 쓴 파일은 같은 암호로 다시 열려 대조된 것이다 — 작업 폴더에는 암호화 파일만 남고, 다른 암호로는 열리지 않는다")
    func exportedFileIsReopenedAndVerified() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }

        // Then: 평문(준비 폴더 · 재검증 폴더)은 지웠고 파일 하나만 남았다.
        let folder = result.fileURL.deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [result.fileURL.lastPathComponent])
        #expect(harness.leftovers() == [folder.lastPathComponent])
        // 같은 암호로 다시 풀면 형식 검증(counts · blob 크기 · 해시 · 지문)을 지나고 수가 결과와 같다.
        let payload = try harness.open(result)
        #expect(payload.manifest.counts == result.counts)
        #expect(result.counts == BackupCounts(rows: 2, drafts: 0, blobs: 3))
        // 다른 암호로는 열리지 않는다.
        #expect(throws: BackupArchiveError.wrongPasswordOrDamaged) {
            _ = try harness.open(result, password: "wrong-password")
        }
    }

    @Test("재검증은 다시 푼 manifest · 항목이 쓴 것과 다르거나 파일이 잘렸으면 실패한다")
    func verificationRejectsAMismatchOrADamagedFile() throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 준비 폴더에 항목 하나를 담아 암호화 파일을 쓴다.
        let work = harness.root.appendingPathComponent("work", isDirectory: true)
        var staging = try BackupExportStaging(directory: work.appendingPathComponent("staged", isDirectory: true))
        let seed = BackupExportRowSeed(verse: 1, rowUUID: "ROW-1", lineData: BackupExportSample.ink("1"), layoutMetadataData: BackupExportSample.metadata)
        try staging.add(BackupExportItems.rowCandidate(seed.record, title: .genesis, isCurrent: true))
        let manifest = try staging.finish(backupID: UUID().uuidString, createdAt: BackupExportSample.now, appVersion: "2.1.0")
        let file = work.appendingPathComponent("backup.carvebackup")
        try BackupArchive.write(stagedDirectory: staging.directory, to: file, password: BackupExportSample.password)
        let scratch = work.appendingPathComponent("verify", isDirectory: true)

        // 맞으면 통과하고 풀린 평문을 지운다.
        try BackupExportVerification.verify(
            file: file, password: BackupExportSample.password, manifest: manifest, items: staging.items, scratch: scratch, limits: .default
        )
        #expect(!FileManager.default.fileExists(atPath: scratch.path))

        // 쓴 것과 다른 항목을 기대하면 실패한다.
        var altered = staging.items
        altered[0].isCurrent = false
        #expect(throws: BackupExportError.verificationFailed) {
            try BackupExportVerification.verify(
                file: file, password: BackupExportSample.password, manifest: manifest, items: altered, scratch: scratch, limits: .default
            )
        }
        // 잘린 파일은 실패한다.
        let bytes = try Data(contentsOf: file)
        try bytes.prefix(bytes.count / 2).write(to: file)
        #expect(throws: BackupExportError.verificationFailed) {
            try BackupExportVerification.verify(
                file: file, password: BackupExportSample.password, manifest: manifest, items: staging.items, scratch: scratch, limits: .default
            )
        }
    }

    @Test("파일 이름 — 부르는 쪽이 준 이름을 다듬어 쓰고, 없으면 「새기다 필사 백업 YYYY-MM-DD.carvebackup」 이다")
    func fileNameIsGivenOrDefault() async throws {
        // 기본 이름은 그레고리력 · 주어진 시간대의 날짜다.
        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSinceReferenceDate: 813_009_600) // 2026-10-06 20:00 UTC = 2026-10-07 05:00 KST
        #expect(BackupExportFileName.defaultName(for: date, timeZone: seoul) == "새기다 필사 백업 2026-10-07.carvebackup")
        #expect(BackupExportFileName.defaultName(for: date, timeZone: utc) == "새기다 필사 백업 2026-10-06.carvebackup")
        // 준 이름 — 경로 구분자 · 앞의 점 · 공백을 다듬고 확장자를 붙인다.
        #expect(BackupExportFileName.sanitized("내 백업") == "내 백업.carvebackup")
        #expect(BackupExportFileName.sanitized("내 백업.carvebackup") == "내 백업.carvebackup")
        #expect(BackupExportFileName.sanitized("a/b:c") == "a-b-c.carvebackup")
        #expect(BackupExportFileName.sanitized("../x") == "-x.carvebackup")
        #expect(BackupExportFileName.sanitized("  ") == nil)
        #expect(BackupExportFileName.sanitized(nil) == nil)

        let harness = try BackupExportHarness()
        defer { harness.remove() }
        let exporter = harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
        let named = try await exporter.export(password: BackupExportSample.password, fileName: "내 백업") { _ in }
        let unnamed = try await exporter.export(password: BackupExportSample.password) { _ in }
        #expect(named.fileURL.lastPathComponent == "내 백업.carvebackup")
        #expect(unnamed.fileURL.lastPathComponent == BackupExportFileName.defaultName(for: BackupExportSample.now))
        // 빈 저장소도 열 수 있는 빈 백업이다.
        #expect(unnamed.counts == BackupCounts(rows: 0, drafts: 0, blobs: 0))
        #expect(try harness.open(unnamed).items.isEmpty)
    }

    @Test("discard 는 그 내보내기의 작업 폴더만 지우고, 작업 폴더 밖의 파일은 건드리지 않는다")
    func discardRemovesOnlyItsWorkDirectory() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)
        let exporter = harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
        let first = try await exporter.export(password: BackupExportSample.password) { _ in }
        let second = try await exporter.export(password: BackupExportSample.password) { _ in }
        let outside = harness.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let stranger = outside.appendingPathComponent("someone.carvebackup")
        try Data("not mine".utf8).write(to: stranger)

        // When
        await exporter.discard(first)
        await exporter.discard(BackupExportResult(fileURL: stranger, counts: first.counts, backupID: first.backupID))

        // Then
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: stranger.path))
    }

    @Test("취소하면 CancellationError 그대로 멈추고 작업 폴더를 남기지 않는다")
    func cancellationLeavesNothing() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try seedTwoChapters(harness)
        let exporter = harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
        let started = AsyncStream<Void>.makeStream()

        // When: 첫 장을 마친 뒤 취소한다.
        let task = Task {
            try await exporter.export(password: BackupExportSample.password) { progress in
                guard progress.done == 1 else { return }
                started.continuation.yield()
                // 취소가 닿을 때까지 이 장 경계에서 기다린다.
                while !Task.isCancelled { await Task.yield() }
            }
        }
        for await _ in started.stream { break }
        task.cancel()

        // Then
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(harness.leftovers().isEmpty)
    }
}
