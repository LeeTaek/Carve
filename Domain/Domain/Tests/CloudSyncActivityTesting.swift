//
//  CloudSyncActivityTesting.swift
//  DomainTest
//
//  앱이 도는 동안 이어지는 동기화 활동 (정책 §4-1).
//

import Foundation
import Testing

@testable import Domain

/// 이전 구현은 초기 import 하나를 확인하면 관찰을 끝냈다. 시작 화면이 지난 뒤의 동기화 상태를
/// 앱이 전혀 알지 못했다는 뜻이다. 이 파일은 그 뒤로 이어지는 누적 규칙을 고정한다.
@Suite("동기화 활동 누적")
struct CloudSyncActivityTesting {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func started(_ kind: CloudSyncEvent.Kind) -> CloudSyncEvent {
        CloudSyncEvent(kind: kind, ended: false, succeeded: false)
    }

    private func finished(_ kind: CloudSyncEvent.Kind, succeeded: Bool) -> CloudSyncEvent {
        CloudSyncEvent(kind: kind, ended: true, succeeded: succeeded)
    }

    @Test("시작 이벤트는 진행 중으로만 표시하고 성공·실패 기록은 건드리지 않는다")
    func startOnlyMarksRunning() {
        let seeded = CloudSyncActivity(lastImportSuccess: now, unresolvedFailures: [.exportFailed])

        let next = seeded.applying(started(.cloudImport), at: later)

        #expect(next.isRunning)
        #expect(next.lastImportSuccess == now)
        #expect(next.unresolvedFailures == [.exportFailed])
    }

    @Test("성공으로 끝난 import·export 는 각자의 시각을 남긴다")
    func successRecordsItsOwnTimestamp() {
        let afterImport = CloudSyncActivity().applying(finished(.cloudImport, succeeded: true), at: now)
        #expect(afterImport.lastImportSuccess == now)
        #expect(afterImport.lastExportSuccess == nil)
        #expect(!afterImport.isRunning)

        let afterExport = afterImport.applying(finished(.cloudExport, succeeded: true), at: later)
        #expect(afterExport.lastImportSuccess == now)
        #expect(afterExport.lastExportSuccess == later)
    }

    /// 받지 못한 것과 올리지 못한 것은 사용자에게 다른 뜻이다.
    @Test("받기 실패와 올리기 실패를 구분한다")
    func importAndExportFailuresDiffer() {
        let importFailed = CloudSyncActivity().applying(finished(.cloudImport, succeeded: false), at: now)
        let exportFailed = CloudSyncActivity().applying(finished(.cloudExport, succeeded: false), at: now)

        #expect(importFailed.unresolvedFailures == [.importFailed])
        #expect(exportFailed.unresolvedFailures == [.exportFailed])
    }

    @Test("같은 종류가 다시 성공하면 그 실패 기록은 지운다")
    func recoveryClearsMatchingFailure() {
        let failed = CloudSyncActivity().applying(finished(.cloudImport, succeeded: false), at: now)
        #expect(failed.unresolvedFailures == [.importFailed])

        let recovered = failed.applying(finished(.cloudImport, succeeded: true), at: later)

        #expect(recovered.unresolvedFailures.isEmpty)
        #expect(recovered.lastImportSuccess == later)
    }

    /// import 가 성공했다고 export 실패가 해결된 것은 아니다 — 내 변경은 여전히 올라가지 못했다.
    @Test("다른 종류의 성공은 남아 있는 실패를 지우지 않는다")
    func unrelatedSuccessKeepsFailure() {
        let exportFailed = CloudSyncActivity().applying(finished(.cloudExport, succeeded: false), at: now)

        let importSucceeded = exportFailed.applying(finished(.cloudImport, succeeded: true), at: later)

        #expect(importSucceeded.unresolvedFailures == [.exportFailed])
        #expect(importSucceeded.lastImportSuccess == later)
    }

    /// ★ 리뷰가 짚은 순서. 이전 구현은 실패를 하나만 들어 import 실패가 export 실패를 덮고, import 성공이 그것을 지웠다.
    @Test("export 실패 → import 실패 → import 성공 뒤에도 export 실패는 남는다")
    func exportFailureSurvivesImportFailureAndRecovery() {
        let activity = CloudSyncActivity()
            .applying(finished(.cloudExport, succeeded: false), at: now)
            .applying(finished(.cloudImport, succeeded: false), at: now)
            .applying(finished(.cloudImport, succeeded: true), at: later)

        #expect(activity.unresolvedFailures == [.exportFailed])
        #expect(activity.summary == .failed([.exportFailed]))
    }

    /// 이전 구현은 setup 실패를 `.unknown` 으로 남기고 setup 성공에서 아무것도 하지 않아, 실패가 끝까지 남았다.
    @Test("setup 실패는 setup 성공으로 풀린다")
    func setupSuccessResolvesSetupFailure() {
        let activity = CloudSyncActivity()
            .applying(finished(.setup, succeeded: false), at: now)
            .applying(finished(.setup, succeeded: true), at: later)

        #expect(activity.unresolvedFailures.isEmpty)
    }

    @Test("setup 실패는 받기 · 올리기 실패와 섞지 않고 따로 남긴다 — 다른 종류의 성공으로 풀리지 않는다")
    func setupFailureIsItsOwnKind() {
        let activity = CloudSyncActivity()
            .applying(finished(.setup, succeeded: false), at: now)
            .applying(finished(.cloudExport, succeeded: true), at: later)

        #expect(activity.unresolvedFailures == [.setupFailed])
        #expect(activity.lastExportSuccess == later)
    }

    @Test("아무 일도 없었으면 성공 기록이 없다 — 동기화됐다고 말할 근거가 없다")
    func emptyActivityHasNoEvidence() {
        let activity = CloudSyncActivity()

        #expect(activity.lastImportSuccess == nil)
        #expect(activity.lastExportSuccess == nil)
        #expect(activity.unresolvedFailures.isEmpty)
        #expect(!activity.isRunning)
    }

    // MARK: 화면 요약

    @Test("기록이 없으면 '아직 주고받은 기록 없음' 이다 — 동기화되지 않았다는 뜻이 아니다")
    func emptyActivitySummarizesAsNoRecord() {
        #expect(CloudSyncActivity().summary == .noRecord)
    }

    @Test("진행 중이면 진행 중으로 요약한다")
    func runningSummarizesAsRunning() {
        #expect(CloudSyncActivity(isRunning: true, lastImportSuccess: now).summary == .running)
    }

    /// 다른 종류의 성공이 있어도, 진행 중이어도 남은 실패는 해결되지 않았다.
    @Test("실패가 가장 먼저다 — 성공 기록이 있거나 진행 중이어도 실패로 요약한다")
    func failureOutranksEverything() {
        let activity = CloudSyncActivity(isRunning: true, lastImportSuccess: now, unresolvedFailures: [.exportFailed])

        #expect(activity.summary == .failed([.exportFailed]))
    }

    @Test("해결되지 않은 실패는 모두 요약하고 범위가 넓은 것부터 둔다 — setup · export · import")
    func allUnresolvedFailuresAreSummarizedInOrder() {
        let activity = CloudSyncActivity(unresolvedFailures: [.importFailed, .setupFailed, .exportFailed])

        #expect(activity.summary == .failed([.setupFailed, .exportFailed, .importFailed]))
    }

    @Test("성공 기록만 있으면 받은 시각과 올린 시각을 각각 든다 — 없는 쪽은 nil")
    func successCarriesEachTimestamp() {
        #expect(CloudSyncActivity(lastImportSuccess: now).summary == .succeeded(lastImport: now, lastExport: nil))
        #expect(CloudSyncActivity(lastImportSuccess: now, lastExportSuccess: later).summary
                == .succeeded(lastImport: now, lastExport: later))
    }
}
