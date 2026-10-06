//
//  BackupImporterCleanupTesting.swift
//  DomainTest
//
//  불러오기의 작업 폴더 · 작업 기록 — 정리, 파일 거부, 기록 내용, 대상 계정 범위 (설계 §4-1 10단계 · §4-2 · §6-2 · §6-3).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 다 쓰거나 닫은 뒤 평문 작업 폴더 · 암호화 사본 · 작업 기록이 남는 것, 검사 실패 뒤 반쯤 만든 것이 남는 것
/// - 잘못된 암호 · 잘린 파일 · 뒤 버전 파일을 저장소를 바꾸기 전에 거부하지 못하는 것
/// - 작업 기록에 암호 · 평문 필기가 남는 것, 멈춘 작업을 닫기만 해도 이어 하기 기록이 사라지는 것
/// - 계정이 확인되지 않았거나 다른 계정 소유인 저장소를 대상 계정으로 잡는 것
@Suite("불러오기 — 작업 폴더 · 작업 기록")
struct BackupImporterCleanupTesting {
    private typealias Sample = BackupRestoreSample

    private var entry: BackupRestoreEntry {
        BackupRestoreEntry(verse: 1, sourceKey: "ROW-1", ink: Sample.ink("1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2))
    }

    @Test("검사 중에는 암호화 사본 · 작업 기록과 평문 작업 폴더가 있고, 다 쓰면 모두 지운다 — 같은 검사 결과로 다시 적용하지 않는다")
    func completedApplyRemovesEverything() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([entry])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When: 검사한다.
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)

        // Then: 작업 기록 폴더에는 암호화 사본(고른 파일과 같은 바이트)과 job.json 만 있다.
        #expect(harness.jobLeftovers() == [inspection.jobID])
        let folder = harness.jobRoot.appendingPathComponent(inspection.jobID, isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["backup.carvebackup", "job.json"])
        #expect(try Data(contentsOf: folder.appendingPathComponent("backup.carvebackup")) == Data(contentsOf: file))
        #expect(harness.workLeftovers().count == 1)
        // 검사만 한 작업은 이어 하기 대상이 아니다.
        #expect(await importer.pendingJob() == nil)

        // When: 적용한다.
        _ = try await importer.apply(inspection) { _ in }

        // Then
        #expect(harness.workLeftovers().isEmpty)
        #expect(harness.jobLeftovers().isEmpty)
        await #expect(throws: BackupImportError.inspectionExpired) {
            _ = try await importer.apply(inspection) { _ in }
        }
        #expect(try await harness.rows().count == 1)
    }

    @Test("검사만 하고 닫으면 평문 작업 폴더 · 암호화 사본 · 작업 기록을 지운다")
    func discardedInspectionRemovesEverything() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([entry])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)

        await importer.discard(inspection)

        #expect(harness.workLeftovers().isEmpty)
        #expect(harness.jobLeftovers().isEmpty)
        await #expect(throws: BackupImportError.inspectionExpired) {
            _ = try await importer.apply(inspection) { _ in }
        }
        #expect(try await harness.rows().isEmpty)
    }

    @Test("잘못된 암호 · 잘린 파일 · 뒤 버전 파일 · 읽을 수 없는 파일은 저장소를 바꾸기 전에 거부하고 아무것도 남기지 않는다")
    func rejectedFilesLeaveNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([entry])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // 잘못된 암호
        await #expect(throws: BackupImportError.wrongPasswordOrDamaged) {
            _ = try await importer.inspect(fileURL: file, password: "wrong-password")
        }
        // 잘린 파일
        let bytes = try Data(contentsOf: file)
        let truncated = harness.files.appendingPathComponent("truncated.carvebackup")
        try bytes.prefix(bytes.count / 2).write(to: truncated)
        await #expect(throws: BackupImportError.wrongPasswordOrDamaged) {
            _ = try await importer.inspect(fileURL: truncated, password: Sample.password)
        }
        // 뒤 버전 형식
        let newer = try harness.writeBackup([entry], formatVersion: 2)
        await #expect(throws: BackupImportError.unsupportedFormat(formatVersion: 2)) {
            _ = try await importer.inspect(fileURL: newer, password: Sample.password)
        }
        // 고른 파일을 읽을 수 없다
        await #expect(throws: BackupImportError.fileUnreadable) {
            _ = try await importer.inspect(fileURL: harness.files.appendingPathComponent("missing.carvebackup"), password: Sample.password)
        }

        #expect(harness.workLeftovers().isEmpty)
        #expect(harness.jobLeftovers().isEmpty)
        #expect(try await harness.rows().isEmpty)
    }

    @Test("멈춘 작업은 닫아도 작업 기록이 남아 이어 할 수 있고, 버리면 지운다")
    func stoppedJobSurvivesDiscardUntilTheJobIsDiscarded() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([entry])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        environment.set(Sample.connectionHeld(Sample.accountA))
        _ = try await importer.apply(inspection) { _ in }

        // When: 결과 화면을 닫는다.
        await importer.discard(inspection)

        // Then: 이어 하기 기록은 남는다.
        #expect(harness.jobLeftovers() == [inspection.jobID])
        let pending = try #require(await importer.pendingJob())
        #expect(pending.jobID == inspection.jobID)

        // When: 버린다.
        await importer.discard(pending)

        // Then
        #expect(harness.jobLeftovers().isEmpty)
        #expect(await importer.pendingJob() == nil)
        await #expect(throws: BackupImportError.jobNotFound) {
            _ = try await importer.resume(pending, password: Sample.password)
        }
    }

    @Test("작업 기록에는 대상 계정 · 상태 · 끝난 장 · 수만 있고 암호 · 평문 필기가 없다 — 사본은 암호화된 그대로다")
    func jobRecordHoldsNoSecrets() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let second = BackupRestoreEntry(
            chapter: Sample.genesis2, verse: 1, sourceKey: "ROW-2", ink: Sample.ink("2"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
        let file = try harness.writeBackup([entry, second])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        _ = try await importer.apply(inspection) { progress in
            if progress.done == 1 { environment.set(Sample.confirmed(Sample.accountB)) }
        }

        // When
        let folder = harness.jobRoot.appendingPathComponent(inspection.jobID, isDirectory: true)
        let json = try Data(contentsOf: folder.appendingPathComponent("job.json"))
        let record = try BackupFormat.decoder.decode(BackupImportJobRecord.self, from: json)
        let copy = try Data(contentsOf: folder.appendingPathComponent("backup.carvebackup"))

        // Then
        #expect(record.jobID == inspection.jobID)
        #expect(record.targetScope == Sample.accountA)
        #expect(record.status == .stopped)
        #expect(record.doneChapters == [Sample.genesis1])
        #expect(record.totalChapters == 2)
        #expect(record.tally == BackupImportTally(new: 1))
        let text = try #require(String(data: json, encoding: .utf8))
        #expect(!text.contains(Sample.password))
        #expect(!text.contains(BackupArchivePassword.encoded(Sample.password)))
        #expect(!text.contains("ink-"))
        #expect(copy.range(of: Data("ink-".utf8)) == nil)
        #expect(copy.range(of: Data("manifest.json".utf8)) == nil)
    }

    @Test("작업 id 가 UUID 가 아니면 작업 기록 폴더 밖을 건드리지 않는다")
    func foreignJobIDTouchesNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let outside = harness.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let forged = BackupImportJob(
            jobID: "../outside", targetScope: Sample.accountA, doneChapters: [], totalChapters: 0, tally: BackupImportTally(),
            updatedAt: Sample.now, canResume: true, writeBlock: nil
        )

        await importer.discard(forged)
        await #expect(throws: BackupImportError.jobNotFound) {
            _ = try await importer.resume(forged, password: Sample.password)
        }
        await #expect(throws: BackupImportError.jobNotFound) {
            _ = try await importer.restart(forged, password: Sample.password)
        }

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("대상 계정 범위는 확인된 계정 · 그 계정 소유 · 쓰기 게이트 열림일 때만이다")
    func targetScopeRule() {
        let owned = Sample.confirmed(Sample.accountA)
        var ownerless = owned
        ownerless.storeOwnership = nil
        var otherOwner = owned
        otherOwner.storeOwnership = Sample.accountB
        var knowledgeUnreadable = owned
        knowledgeUnreadable.knowledge = nil
        var tokenless = owned
        tokenless.serverWork = nil
        let unconfirmed = DrawingEditEnvironment(
            accountState: .unconfirmed(lastConfirmed: Sample.accountA), serverWork: nil, knowledge: EraseEpochKnowledge(), storeOwnership: Sample.accountA
        )

        #expect(LiveBackupImporter.targetScope(for: owned) == Sample.accountA)
        for environment in [ownerless, otherOwner, knowledgeUnreadable, tokenless, unconfirmed, Sample.signedOut, Sample.connectionHeld(Sample.accountA)] {
            #expect(LiveBackupImporter.targetScope(for: environment) == nil)
        }
    }
}
