//
//  CloudSyncStateRuleTesting.swift
//  DomainTest
//
//  동기화 상태 판정 — "끝난 것" 과 "성공한 것" 을 가른다.
//

import Foundation
import Testing

@testable import Domain

/// 이전 구현은 `endDate != nil` 과 `type == .import` 만 보고 완료로 판정했다.
/// 그래서 **오류로 끝난 import 도 "데이터 동기화 완료" 로 표시**됐다.
/// 이 파일은 그 회귀를 막는다.
@Suite("CloudKit 동기화 상태 판정")
struct CloudSyncStateRuleTesting {

    private func event(_ kind: CloudSyncEvent.Kind, ended: Bool, succeeded: Bool) -> CloudSyncEvent {
        CloudSyncEvent(kind: kind, ended: ended, succeeded: succeeded)
    }

    @Test("성공으로 끝난 import 만 완료로 본다")
    func onlySucceededImportCompletes() {
        let succeeded = event(.cloudImport, ended: true, succeeded: true)

        #expect(CloudSyncStateRule.isAwaitedImportSuccess(succeeded))
        #expect(!CloudSyncStateRule.isImportFailure(succeeded))
        #expect(CloudSyncStateRule.concludesWaiting(succeeded))
    }

    /// ★ 이전 구현이 완료로 오판하던 바로 그 경우다.
    @Test("오류로 끝난 import 는 완료가 아니라 실패다")
    func failedImportIsNotCompletion() {
        let failed = event(.cloudImport, ended: true, succeeded: false)

        #expect(!CloudSyncStateRule.isAwaitedImportSuccess(failed))
        #expect(CloudSyncStateRule.isImportFailure(failed))
        // 대기를 끝낼 근거는 된다 — 다만 그 결론이 "완료" 가 아니라 "실패" 다.
        #expect(CloudSyncStateRule.concludesWaiting(failed))
    }

    @Test("진행 중인 import 는 성공도 실패도 아니다")
    func runningImportConcludesNothing() {
        // 아직 끝나지 않았으므로 succeeded 값은 의미가 없다. 둘 다 결론이 아니어야 한다.
        for succeeded in [true, false] {
            let running = event(.cloudImport, ended: false, succeeded: succeeded)
            #expect(!CloudSyncStateRule.isAwaitedImportSuccess(running))
            #expect(!CloudSyncStateRule.isImportFailure(running))
            #expect(!CloudSyncStateRule.concludesWaiting(running))
        }
    }

    @Test("초기 import 를 기다리는 동안 setup·export 는 결론이 되지 않는다",
          arguments: [CloudSyncEvent.Kind.setup, .cloudExport])
    func otherKindsDoNotConclude(kind: CloudSyncEvent.Kind) {
        #expect(!CloudSyncStateRule.concludesWaiting(event(kind, ended: true, succeeded: true)))
        #expect(!CloudSyncStateRule.concludesWaiting(event(kind, ended: true, succeeded: false)))
    }

    @Test("기다리는 중인 상태에서만 진행 표시를 켠다")
    func inProgressStates() {
        typealias State = PersistentCloudKitContainer.CloudSyncState

        #expect(State.idle.isInProgress)
        #expect(State.syncing.isInProgress)
        #expect(State.migration.isInProgress)
        // 제한 시간이 지난 것은 실패가 아니다. 관찰이 이어지므로 진행 중으로 본다 (정책 §3).
        #expect(State.stillWaiting.isInProgress)

        #expect(!State.syncCompleted.isInProgress)
        #expect(!State.migrationCompleted.isInProgress)
        #expect(!State.failed(.accountUnavailable).isInProgress)
    }

    @Test("실패는 원인을 잃지 않는다 — 원인이 다르면 다른 상태다")
    func failureKeepsItsReason() {
        typealias State = PersistentCloudKitContainer.CloudSyncState

        #expect(State.failed(.accountUnavailable) != State.failed(.importFailed))
        #expect(State.failed(.unknown) != State.failed(.accountUnavailable))
        #expect(State.failed(.importFailed) == State.failed(.importFailed))
        // 기다리는 중과 실패를 같은 상태로 뭉치지 않는다.
        #expect(State.stillWaiting != State.failed(.unknown))
    }
}
