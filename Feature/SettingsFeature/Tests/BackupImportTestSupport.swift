//
//  BackupImportTestSupport.swift
//  SettingsFeatureTest
//
//  「백업 불러오기」 시험의 공용 준비물 — 고정 값 · 불러오기 대역 · 보안 범위 접근 기록 · TestStore.
//

@testable import SettingsFeature
import Domain
import Foundation

import ComposableArchitecture

/// 불러오기 시험이 보는 사건 — 불러오기 대역과 보안 범위 접근 대역이 같은 기록에 부른 순서대로 적는다.
enum ImportEvent: Equatable, Sendable {
    /// 고른 파일의 보안 범위 접근을 열려고 했다.
    case accessOpened(URL)
    /// 연 접근을 닫았다.
    case accessClosed(URL)
    /// 끝나지 않은 불러오기를 읽었다.
    case pendingJobRead
    /// 고른 파일을 검사했다 — 넘긴 암호가 맞는지 보려고만 적는다.
    case inspected(URL, password: String)
    /// 멈춘 작업을 이었다.
    case resumed(jobID: String, password: String)
    /// 멈춘 작업의 사본으로 처음부터 검사했다.
    case restarted(jobID: String, password: String)
    /// 검사 결과를 적용했다.
    case applied(jobID: String)
    /// 검사 결과를 닫았다(평문 작업 폴더 정리).
    case inspectionDiscarded(jobID: String)
    /// 멈춘 작업을 버렸다.
    case jobDiscarded(jobID: String)
}

/// 불러오기 시험의 고정 값.
enum ImportFixture {
    static let account = AccountScope(key: "acct-0123456789abcdef0123456789abcdef")
    static let fileURL = URL(fileURLWithPath: "/tmp/Picked/새기다 필사 백업 2026-10-06.carvebackup")
    static let password = "abcd1234"
    static let jobID = "00000000-0000-0000-0000-0000000000C1"
    static let otherJobID = "00000000-0000-0000-0000-0000000000C2"
    /// 판정 · 적용 · 작업 기록의 단위는 필사책 안의 장이다(형식 2) — 기본 필사책의 장.
    static let genesis1 = NotebookChapter(notebook: .default, chapter: BibleChapter(title: .genesis, chapter: 1))
    static let genesis2 = NotebookChapter(notebook: .default, chapter: BibleChapter(title: .genesis, chapter: 2))
    static let exodus3 = NotebookChapter(notebook: .default, chapter: BibleChapter(title: .exodus, chapter: 3))

    /// 검사 때의 미리보기.
    static let preview = BackupImportPreview(
        new: 3,
        same: 2,
        archived: 4,
        protectedCleared: 1,
        skippedEmpty: 1,
        unsupported: [.unknownBook: 1, .undecodableMetadata: 2],
        chapters: [genesis1, genesis2, exodus3]
    )

    /// 적용한 장들의 실제 수 — 미리보기와 일부러 다르다(쓰기 직전에 다시 판정한다).
    static let tally = BackupImportTally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2, pinned: 1)

    /// 검사 결과 — 기본은 대상 계정이 있어 적용할 수 있다.
    static func inspection(
        jobID: String = jobID,
        targetScope: AccountScope? = account,
        writeBlock: SyncedWriteBlock? = nil,
        doneChapters: [NotebookChapter] = []
    ) -> BackupInspection {
        BackupInspection(jobID: jobID, targetScope: targetScope, writeBlock: writeBlock, preview: preview, doneChapters: doneChapters)
    }

    /// 끝나지 않은 작업 — 3장 중 1장을 넣었다.
    static func job(canResume: Bool, writeBlock: SyncedWriteBlock? = nil, jobID: String = jobID) -> BackupImportJob {
        BackupImportJob(
            jobID: jobID,
            targetScope: account,
            doneChapters: [genesis1],
            totalChapters: 3,
            tally: BackupImportTally(new: 2, same: 1, archived: 1),
            updatedAt: BackupTestTime.now,
            canResume: canResume,
            writeBlock: writeBlock
        )
    }
}

/// 정해 둔 결과를 돌려주는 불러오기 대역. 부른 순서를 `log` 에 적는다.
final class StubBackupImporter: BackupImporting {
    let log: LockIsolated<[ImportEvent]>
    /// 지금 끝나지 않은 작업 — `discard(_ job:)` 하면 `afterDiscard` 로 바뀐다.
    let pending: LockIsolated<BackupImportJob?>
    private let afterDiscard: BackupImportJob?
    /// 검사 · 이어 하기 · 처음부터의 결과.
    private let inspection: Result<BackupInspection, BackupImportError>
    /// 적용의 결과.
    private let report: Result<BackupImportReport, BackupImportError>
    /// 적용 결과 전에 알릴 진행.
    private let applySteps: [BackupProgress]
    /// true 면 검사가 취소될 때까지 끝나지 않는다.
    private let suspendsInspection: Bool
    /// true 면 적용이 취소될 때까지 끝나지 않는다.
    private let suspendsApply: Bool

    init(
        log: LockIsolated<[ImportEvent]>,
        pending: BackupImportJob? = nil,
        afterDiscard: BackupImportJob? = nil,
        inspection: Result<BackupInspection, BackupImportError> = .success(ImportFixture.inspection()),
        report: Result<BackupImportReport, BackupImportError> = .success(.completed(ImportFixture.tally)),
        applySteps: [BackupProgress] = [],
        suspendsInspection: Bool = false,
        suspendsApply: Bool = false
    ) {
        self.log = log
        self.pending = LockIsolated(pending)
        self.afterDiscard = afterDiscard
        self.inspection = inspection
        self.report = report
        self.applySteps = applySteps
        self.suspendsInspection = suspendsInspection
        self.suspendsApply = suspendsApply
    }

    func pendingJob() async -> BackupImportJob? {
        log.withValue { $0.append(.pendingJobRead) }
        return pending.value
    }

    func inspect(fileURL: URL, password: String) async throws -> BackupInspection {
        log.withValue { $0.append(.inspected(fileURL, password: password)) }
        return try await finishInspection()
    }

    func resume(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        log.withValue { $0.append(.resumed(jobID: job.jobID, password: password)) }
        return try await finishInspection()
    }

    func restart(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        log.withValue { $0.append(.restarted(jobID: job.jobID, password: password)) }
        return try await finishInspection()
    }

    func apply(_ inspection: BackupInspection, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupImportReport {
        log.withValue { $0.append(.applied(jobID: inspection.jobID)) }
        for step in applySteps {
            await progress(step)
        }
        if suspendsApply {
            try await Task<Never, Never>.never()
        }
        return try report.get()
    }

    func discard(_ inspection: BackupInspection) async {
        log.withValue { $0.append(.inspectionDiscarded(jobID: inspection.jobID)) }
    }

    func discard(_ job: BackupImportJob) async {
        log.withValue { $0.append(.jobDiscarded(jobID: job.jobID)) }
        pending.setValue(afterDiscard)
    }

    /// 검사 · 이어 하기 · 처음부터의 끝 — 정해 둔 결과(또는 취소될 때까지 기다림).
    private func finishInspection() async throws -> BackupInspection {
        if suspendsInspection {
            try await Task<Never, Never>.never()
        }
        return try inspection.get()
    }
}

extension BackupFileAccessClient {
    /// 여닫음을 `log` 에 적는 대역. `grants` 가 false 면 보안 범위가 아닌 URL 처럼 열리지 않는다(그때는 닫지 않아야 한다).
    static func recording(_ log: LockIsolated<[ImportEvent]>, grants: Bool = true) -> Self {
        Self(
            open: { url in
                log.withValue { $0.append(.accessOpened(url)) }
                return grants
            },
            close: { url in
                log.withValue { $0.append(.accessClosed(url)) }
            }
        )
    }
}

/// 「백업 불러오기」 TestStore — 불러오기 대역 · 보안 범위 접근 기록 · 닫힘 횟수를 넣는다.
@MainActor
func makeImportStore(
    _ state: BackupImportFeature.State = BackupImportFeature.State(),
    importer: StubBackupImporter?,
    log: LockIsolated<[ImportEvent]>,
    grantsAccess: Bool = true,
    dismissals: LockIsolated<Int> = LockIsolated(0)
) -> TestStoreOf<BackupImportFeature> {
    TestStore(initialState: state) {
        BackupImportFeature()
    } withDependencies: {
        $0.backupImporter = importer
        $0.backupFileAccess = .recording(log, grants: grantsAccess)
        $0.dismiss = DismissEffect { dismissals.withValue { $0 += 1 } }
    }
}

/// 끝나지 않는 대역이 정말 불릴 때까지 기다린다 — 그 effect 를 멈추기(닫기) 전에 대역까지 닿았음을 보장한다.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    var attempts = 0
    while !condition(), attempts < 10_000 {
        attempts += 1
        await Task.yield()
    }
}

extension BackupImportFeature.State {
    /// 그 단계에 있는 상태.
    static func at(_ step: BackupImportFeature.Step, password: String = "") -> Self {
        var state = Self()
        state.step = step
        state.password = password
        return state
    }
}
