//
//  BackupImporterFlowTesting.swift
//  DomainTest
//
//  불러오기 적용 흐름 — 장마다 최신 환경 · 쓰기 게이트 · 대상 계정, 이어 하기, 재시도 멱등, 미리보기 뒤 재판정 (설계 §4-3 · §6).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 적용 도중 다른 계정으로 바뀌었는데 계속 써 B 계정 저장소에 A 계정의 불러오기를 잇는 것, 그 작업을 B 계정에서 이어 하게 내놓는 것
/// - 쓰기 게이트가 막힌 실행(로그아웃 · 연결 보류)에서 저장소에 쓰는 것
/// - 중간 장 실패 뒤 재시도가 행을 늘리는 것, 같은 파일을 다시 불러오면 행이 늘어나는 것
/// - 미리보기 뒤 같은 절에 들어온 필기를 덮듯이 현재로 넣는 것, 적용 중 「모든 필사 삭제」 뒤에 옛 판정으로 계속 쓰는 것
@Suite("불러오기 — 적용 흐름")
struct BackupImporterFlowTesting {
    private typealias Sample = BackupRestoreSample

    /// 장마다 현재 필기 하나.
    private func current(_ chapter: BibleChapter, verse: Int = 1) -> BackupRestoreEntry {
        BackupRestoreEntry(
            chapter: chapter, verse: verse, sourceKey: "ROW-\(chapter.title.rawValue)-\(chapter.chapter)-\(verse)",
            ink: Sample.ink("\(chapter.title.rawValue)-\(chapter.chapter)-\(verse)"), isCurrent: true,
            createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
    }

    @Test("적용 중 다른 계정으로 바뀌면 그 장부터 0건 쓰고 accountChanged — 쓴 장은 그대로, 작업 기록은 남는다")
    func accountChangeStopsAtTheNextChapter() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2)])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)

        // When: 첫 장을 쓴 뒤 B 계정으로 바뀐다.
        let report = try await importer.apply(inspection) { progress in
            if progress.done == 1 { environment.set(Sample.confirmed(Sample.accountB)) }
        }

        // Then
        #expect(report == .accountChanged(doneChapters: [Sample.genesis1], tally: BackupImportTally(new: 1)))
        #expect(try await harness.rows(Sample.genesis1).count == 1)
        #expect(try await harness.rows(Sample.genesis2).isEmpty)
        #expect(harness.changes.posted.map(\.chapter) == [Sample.genesis1])
        #expect(harness.workLeftovers().isEmpty)
        #expect(harness.jobLeftovers() == [inspection.jobID])
    }

    @Test("검사 뒤 적용 전에 다른 계정 저장소로 바뀌었으면 첫 장부터 0건 — 쓸 수 있는 B 계정이어도 accountChanged")
    func accountChangeBeforeApplyWritesNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2)])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)

        // When: A 계정에서 검사했는데, 적용할 때는 쓰기 게이트가 열린 B 계정 저장소다.
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        environment.set(Sample.confirmed(Sample.accountB))
        let report = try await importer.apply(inspection) { _ in }

        // Then
        #expect(inspection.targetScope == Sample.accountA)
        #expect(report == .accountChanged(doneChapters: [], tally: BackupImportTally()))
        #expect(try await harness.rows(Sample.genesis1).isEmpty)
        #expect(try await harness.rows(Sample.genesis2).isEmpty)

        // When: 같은 계정 · 같은 표인데 저장소 소유 근거만 B 로 바뀌었다.
        environment.set(Sample.confirmed(Sample.accountA))
        let again = try await importer.inspect(fileURL: file, password: Sample.password)
        var foreign = Sample.confirmed(Sample.accountA)
        foreign.storeOwnership = Sample.accountB
        environment.set(foreign)
        let blocked = try await importer.apply(again) { _ in }

        // Then: 쓰기 게이트가 소유 근거 없음으로 막는다.
        #expect(blocked == .blocked(.ownershipUnverified, doneChapters: [], tally: BackupImportTally()))
        #expect(try await harness.rows(Sample.genesis1).isEmpty)
        #expect(harness.changes.posted.isEmpty)
    }

    @Test("A 계정에서 멈춘 작업은 B 계정 환경에서 이어 하지 않고, A 로 돌아오면 끝난 장을 건너뛰고 잇는다")
    func otherAccountJobIsNotResumed() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2)])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        _ = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { progress in
            if progress.done == 1 { environment.set(Sample.confirmed(Sample.accountB)) }
        }

        // When: B 계정 환경에서 끝나지 않은 작업을 본다.
        let pendingInB = try #require(await importer.pendingJob())

        // Then: 다른 계정 작업 — 이어 하지 못한다(버리기 · 처음부터만). 이어 하려 해도 거절하고 기록은 남는다.
        #expect(pendingInB.targetScope == Sample.accountA)
        #expect(pendingInB.doneChapters == [Sample.genesis1])
        #expect(pendingInB.totalChapters == 2)
        #expect(!pendingInB.canResume)
        await #expect(throws: BackupImportError.jobFromOtherAccount) {
            _ = try await importer.resume(pendingInB, password: Sample.password)
        }
        #expect(harness.jobLeftovers() == [pendingInB.jobID])
        #expect(harness.workLeftovers().isEmpty)

        // When: A 계정으로 돌아와 암호를 다시 넣고 잇는다.
        environment.set(Sample.confirmed(Sample.accountA))
        let pendingInA = try #require(await importer.pendingJob())
        #expect(pendingInA.canResume)
        let resumed = try await importer.resume(pendingInA, password: Sample.password)
        #expect(resumed.jobID == pendingInA.jobID)
        #expect(resumed.doneChapters == [Sample.genesis1])
        let report = try await importer.apply(resumed) { _ in }

        // Then: 남은 장만 썼고 끝난 장은 다시 쓰지 않았다. 다 끝나 작업 기록을 지웠다.
        #expect(report == .completed(BackupImportTally(new: 2)))
        #expect(try await harness.rows(Sample.genesis1).count == 1)
        #expect(try await harness.rows(Sample.genesis2).count == 1)
        #expect(harness.changes.posted.map(\.chapter) == [Sample.genesis1, Sample.genesis2])
        #expect(await importer.pendingJob() == nil)
        #expect(harness.jobLeftovers().isEmpty)
    }

    @Test("다른 계정 작업은 「이 계정으로 처음부터」 — 새 대상 계정으로 다시 검사하고 옛 작업은 지운다")
    func restartUnderTheCurrentAccount() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2)])
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        _ = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { progress in
            if progress.done == 1 { environment.set(Sample.confirmed(Sample.accountB)) }
        }
        let pending = try #require(await importer.pendingJob())

        // When: B 계정에서 처음부터 한다.
        let restarted = try await importer.restart(pending, password: Sample.password)

        // Then: 새 작업 · 새 대상 계정 · 끝난 장 없음. 옛 작업은 지웠다.
        #expect(restarted.jobID != pending.jobID)
        #expect(restarted.targetScope == Sample.accountB)
        #expect(restarted.doneChapters.isEmpty)
        #expect(harness.jobLeftovers() == [restarted.jobID])
        // 적용하면 이미 넣은 장은 같은 내용이라 건너뛰고 남은 장을 쓴다.
        let report = try await importer.apply(restarted) { _ in }
        #expect(report == .completed(BackupImportTally(new: 1, same: 1)))
        #expect(try await harness.rows(Sample.genesis1).count == 1)
        #expect(try await harness.rows(Sample.genesis2).count == 1)
        #expect(harness.jobLeftovers().isEmpty)
    }

    @Test("쓰기 게이트가 막히면 그 장부터 0건 쓰고 사유를 돌려준다 — 적용 중 연결 보류, 검사 때부터 로그아웃")
    func blockedWriteGateWritesNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1)])

        // When: 검사는 A 계정에서 했는데 적용할 때는 연결이 보류됐다.
        let environment = SwitchableBackupEnvironment(Sample.confirmed(Sample.accountA))
        let importer = harness.importer(environment)
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        environment.set(Sample.connectionHeld(Sample.accountA))
        let held = try await importer.apply(inspection) { _ in }

        // Then
        #expect(held == .blocked(.connectionHeld, doneChapters: [], tally: BackupImportTally()))
        #expect(try await harness.rows().isEmpty)
        let pending = try #require(await importer.pendingJob())
        #expect(!pending.canResume)
        #expect(pending.writeBlock == .connectionHeld)

        // When: 로그아웃한 실행 — 검사 · 미리보기는 되지만 대상 계정이 없다.
        let signedOut = harness.importer(StubDrawingEditEnvironment(Sample.signedOut))
        let preview = try await signedOut.inspect(fileURL: file, password: Sample.password)

        // Then: 미리보기까지 — 적용하면 쓰지 않고 사유를 돌려준다.
        #expect(preview.targetScope == nil)
        #expect(preview.writeBlock == .signedOut)
        #expect(!preview.canApply)
        #expect(preview.preview.new == 1)
        let report = try await signedOut.apply(preview) { _ in }
        #expect(report == .blocked(.signedOut, doneChapters: [], tally: BackupImportTally()))
        #expect(try await harness.rows().isEmpty)
        #expect(harness.changes.posted.isEmpty)
    }

    @Test("중간 장에서 쓰기에 실패해도 쓴 장은 그대로이고, 다시 이어 하면 남은 장만 써 행이 늘지 않는다")
    func retryAfterMiddleFailureIsIdempotent() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entries = [current(Sample.genesis1), current(Sample.genesis2), current(Sample.exodus3)]
        let file = try harness.writeBackup(entries)
        let importer = harness.importer(
            StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)),
            restorer: FailingOnceRestorer(base: harness.restorer, failing: Sample.genesis2)
        )

        // When: 둘째 장에서 쓰기에 실패한다.
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        await #expect(throws: BackupImportError.storeWriteFailed) {
            _ = try await importer.apply(inspection) { _ in }
        }

        // Then: 첫 장만 썼고 작업 기록이 그 장을 끝남으로 들고 있다. 평문은 지웠다.
        #expect(try await harness.rows(Sample.genesis1).count == 1)
        #expect(try await harness.rows(Sample.genesis2).isEmpty)
        #expect(try await harness.rows(Sample.exodus3).isEmpty)
        #expect(harness.workLeftovers().isEmpty)
        let pending = try #require(await importer.pendingJob())
        #expect(pending.doneChapters == [Sample.genesis1])
        #expect(pending.canResume)

        // When: 암호를 다시 넣고 잇는다.
        let report = try await importer.apply(try await importer.resume(pending, password: Sample.password)) { _ in }

        // Then: 장마다 한 행 — 늘지 않았다. 수는 앞 실행까지 더한 것이다.
        #expect(report == .completed(BackupImportTally(new: 3)))
        for chapter in [Sample.genesis1, Sample.genesis2, Sample.exodus3] {
            #expect(try await harness.rows(chapter).count == 1, "\(chapter.title.rawValue).\(chapter.chapter)")
        }

        // Then: 같은 파일을 다시 불러와도 전부 같은 내용이라 0건이다.
        let again = try await importer.inspect(fileURL: file, password: Sample.password)
        #expect(again.preview.same == 3)
        #expect(again.preview.insertCount == 0)
        let repeated = try await importer.apply(again) { _ in }
        #expect(repeated == .completed(BackupImportTally(same: 3)))
        for chapter in [Sample.genesis1, Sample.genesis2, Sample.exodus3] {
            #expect(try await harness.rows(chapter).count == 1)
        }
    }

    @Test("같은 파일을 다시 불러오면 추가 0건이다 — 전부 skipSame, 변경 알림도 없다")
    func repeatedImportAddsNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entries = [
            BackupRestoreEntry(verse: 1, sourceKey: "ROW-1", ink: Sample.ink("1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(10)),
            BackupRestoreEntry(verse: 1, sourceKey: "ROW-1-OLD", ink: Sample.ink("1-old"), isCurrent: false, createdAt: Sample.sep(1), updatedAt: Sample.sep(5)),
            BackupRestoreEntry(verse: 2, sourceKey: "ROW-2-CLEARED", ink: nil, isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(30)),
            BackupRestoreEntry(verse: 2, sourceKey: "ROW-2-ERASED", ink: Sample.ink("2"), isCurrent: false, createdAt: Sample.sep(30), updatedAt: Sample.sep(25))
        ]
        let file = try harness.writeBackup(entries)
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let first = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { _ in }
        #expect(first == .completed(BackupImportTally(new: 2, archived: 2)))
        let rowsAfterFirst = try await harness.rows()
        let postedAfterFirst = harness.changes.posted

        // When
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        let second = try await importer.apply(inspection) { _ in }

        // Then
        #expect(inspection.preview == BackupImportPreview(same: 4, chapters: [Sample.genesis1]))
        #expect(second == .completed(BackupImportTally(same: 4)))
        #expect(try await harness.rows() == rowsAfterFirst)
        #expect(harness.changes.posted == postedAfterFirst)
    }

    @Test("미리보기 뒤 같은 절에 다른 필기가 들어오면 쓰기 직전에 다시 판정해 보관으로만 넣는다")
    func rejudgesAfterThePreview() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1)])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        #expect(inspection.preview.new == 1)

        // When: 미리보기 뒤 다른 기기에서 그 절의 필기가 도착했다.
        let arrived = BackupExportRowSeed(
            verse: 1, rowUUID: "ARRIVED", creationDate: Sample.sep(3), updateDate: Sample.sep(29),
            lineData: Sample.ink("arrived"), layoutMetadataData: Sample.metadata
        )
        try harness.seed([arrived])
        let report = try await importer.apply(inspection) { _ in }

        // Then: 실제 결정은 보관 — 도착한 필기가 그대로 대표다.
        #expect(report == .completed(BackupImportTally(archived: 1)))
        #expect(try await harness.representative(verse: 1)?.rowKey == "ARRIVED")
        #expect(try await harness.rows().count == 2)
    }

    @Test("적용 중 「모든 필사 삭제」 로 세대가 바뀌면 그 장부터 멈추고, 지워진 끝난 장은 작업 기록에서도 비운다")
    func generationChangeStopsAndClearsProgress() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2)])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        let database = harness.database

        // When: 첫 장을 쓴 뒤 모든 필사를 지운다.
        let report = try await importer.apply(inspection) { progress in
            if progress.done == 1 { try? await database.eraseAllDrawingRows() }
        }

        // Then
        #expect(report == .generationChanged(doneChapters: [], tally: BackupImportTally()))
        #expect(try await harness.rows(Sample.genesis1).isEmpty)
        #expect(try await harness.rows(Sample.genesis2).isEmpty)
        let pending = try #require(await importer.pendingJob())
        #expect(pending.doneChapters.isEmpty)
        #expect(pending.canResume)
    }

    @Test("진행은 장 단위다 — 시작에 이미 끝난 장 수, 장마다 한 번")
    func reportsProgressPerChapter() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let file = try harness.writeBackup([current(Sample.genesis1), current(Sample.genesis2), current(Sample.exodus3)])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        let recorder = BackupProgressRecorder()

        _ = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { recorder.record($0) }

        #expect(recorder.events == (0...3).map { BackupProgress(done: $0, total: 3) })
    }
}
