//
//  ChapterCanvasEditSessionBasisTesting.swift
//  CarveFeatureTest
//
//  편집 세션의 근거 — 한 세션은 한 근거(계정 상태 · K · 소유 근거)로 읽은 내용만 들고, 근거 없이 귀속하지 않는다 (정책 §12-6 구현 순서 ①).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 다른 계정 · K 로 읽은 조회 결과를 지금 세션에 섞는 것(세대 비교로는 막지 못한다 — 8차 리뷰)
/// - 저장소 소유 근거 없이 편집을 계정에 귀속하는 것(마지막 확인 계정 · 계정 확인 완료는 근거가 아니다 — 6 · 7차 리뷰)
/// - 앞서 정리된 세션의 늦은 격리 응답이 지금 닫는 세션을 건드리는 것
@Suite("편집 세션 — 조회 근거 · 소유 근거 · 보존만")
@MainActor
struct ChapterCanvasEditSessionBasisTesting: EditSessionTestHelpers {
    // MARK: - 조회와 환경

    /// 옛 계정으로 읽은 내용을 새 세션 아래 합성하면, 그 위의 편집이 다른 계정 데이터에 기대게 된다(6차 리뷰 4).
    @Test("조회하는 사이 계정이 바뀌면 옛 조회 결과를 버리고 새 환경으로 다시 읽는다")
    func accountChangeDuringLoadDiscardsOldResult() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [], environment: environment, quarantine: quarantine)
        spy.holdNextLoadCall()
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        while environment.subscriberCount == 0 { await Task.yield() }
        let heldRequest = store.state.loadRequestID

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.loadRequestID != heldRequest)
        await store.receive(\.drawingsLoaded)
        let freshRequest = store.state.loadRequestID

        // 붙잡혀 있던 옛 조회가 이제 끝난다 — 결과는 버려진다.
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)

        #expect(store.state.loadRequestID == freshRequest)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(spy.loadedChapters.value.count == 2)
        await end(store, environment)
    }

    /// 세대는 소유도 K 의 동등성도 나타내지 않는다(8차 리뷰). 같은 세대에 K 만 다른 결과가 귀속 세션에 섞이면, 삭제를 모르는 내용
    /// 위의 편집이 귀속된다. 호출부의 선행 알림 없이 결과가 도착한 경우를 재현하려고 결과를 직접 보낸다.
    @Test("같은 세대여도 다른 K 로 읽은 결과는 섞지 않고, 지킬 편집을 지금 세션의 출처로 보존한 뒤 새 근거로 다시 연다")
    func differentBasisResultIsNotMixedIntoSession() async throws {
        let spy = RepositorySpy()
        let session = confirmed(accountA, 1)
        let environment = ControlledEditEnvironment(session)
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        var learned = EraseEpochKnowledge()
        learned.receive("E1")
        let otherBasis = confirmed(accountA, 1, knowledge: learned)
        environment.environment.setValue(otherBasis)
        let requestID = try #require(store.state.loadRequestID)

        await store.send(.drawingsLoaded(
            requestID: requestID, environment: otherBasis,
            .success(DrawingChapterLoad(snapshots: [], generation: DrawingStoreGeneration(raw: 0)))
        ))

        #expect(store.state.sessionEnd?.environment == session)
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)
        #expect(quarantine.calls.value.first?.environment == session)
        #expect(store.state.editEnvironment == otherBasis)
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    @Test("지킬 편집이 없으면 다른 계정으로 읽은 결과의 근거로 새 세션을 연다")
    func differentBasisResultStartsNewSessionWhenNothingToProtect() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        let requestID = try #require(store.state.loadRequestID)

        await store.send(.drawingsLoaded(
            requestID: requestID, environment: confirmed(accountB, 2),
            .success(DrawingChapterLoad(snapshots: [], generation: DrawingStoreGeneration(raw: 0)))
        ))

        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(store.state.sessionEnd == nil)
        #expect(quarantine.calls.value.isEmpty)
        await end(store, environment)
    }

    // MARK: - 보존만

    /// 마지막 확인 계정과 같다는 것은 귀속 근거가 아니다(6차 리뷰 3). 편집은 보존하되 세션을 그 계정으로 올리지 않는다.
    @Test("확인 전에 시작한 세션은 같은 계정으로 확인돼도 귀속하지 않고, 지킬 편집이 없어진 뒤 새 세션으로 연다")
    func unverifiedSessionIsNotPromotedByHint() async {
        let spy = RepositorySpy()
        let unverified = DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                knowledge: EraseEpochKnowledge())
        let environment = ControlledEditEnvironment(unverified)
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)

        environment.change(to: confirmed(accountA, 1))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == unverified)
        #expect(quarantine.calls.value.isEmpty)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        environment.change(to: confirmed(accountA, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.editEnvironment == confirmed(accountA, 2))
        #expect(quarantine.calls.value.isEmpty)
        await end(store, environment)
    }

    /// 읽지 못한 K 를 빈 집합으로 다루면 삭제 사실을 잊은 채 편집을 귀속한다.
    @Test("K 를 읽지 못한 채 시작한 세션은 보존만 하고, 지킬 편집이 없어진 뒤 읽힌 K 로 새 세션을 연다")
    func unreadableKnowledgeSessionIsPreserveOnly() async {
        let spy = RepositorySpy()
        let blind = confirmed(accountA, 1, knowledge: nil)
        let environment = ControlledEditEnvironment(blind)
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        var learned = EraseEpochKnowledge()
        learned.receive("E1")

        environment.change(to: confirmed(accountA, 1, knowledge: learned))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == blind)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        environment.change(to: confirmed(accountA, 2, knowledge: learned))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.editEnvironment == confirmed(accountA, 2, knowledge: learned))
        await end(store, environment)
    }

    // MARK: - 소유 근거

    /// 계정 확인이 끝나도 저장소에는 이전 계정의 필사가 남아 있을 수 있다(7차 리뷰). 근거 없이 귀속하지 않는다.
    @Test("확인된 계정에서 시작해도 저장소 소유 근거가 없으면 새 표를 들지 않고 보존만 한다")
    func confirmedSessionWithoutOwnershipIsPreserveOnly() async {
        let spy = RepositorySpy()
        let unowned = confirmed(accountA, 1, owned: false)
        let environment = ControlledEditEnvironment(unowned)
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)

        environment.change(to: confirmed(accountA, 2, owned: false))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.editEnvironment == unowned)
        #expect(store.state.sessionEnd == nil)
        #expect(quarantine.calls.value.isEmpty)
        spy.releaseApply()
        await store.receive(\.saveFinished)
        await end(store, environment)
    }

    // MARK: - 늦은 격리 응답

    /// 전체 삭제로 정리된 뒤 새로 닫는 세션이 생겼을 때, 앞 세션 격리의 늦은 성공 응답이 새 세션의 미저장분을 치우면 안 된다(7차 리뷰 3).
    @Test("다른 세션의 격리 응답은 지금 닫는 세션의 미저장분을 건드리지 않는다")
    func staleQuarantineCompletionIsIgnored() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("disk")])
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        quarantine.holdNextCall()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.sessionEndSettled)
        guard case .quarantining = store.state.sessionEnd?.phase else {
            Issue.record("격리가 시작되지 않았다: \(String(describing: store.state.sessionEnd))")
            return
        }

        await store.send(.sessionQuarantineFinished(id: "앞서 정리된 세션", failure: nil))
        #expect(!store.state.pendingMutations.isEmpty)
        guard case .quarantining = store.state.sessionEnd?.phase else {
            Issue.record("늦은 응답이 지금 격리를 끝냈다: \(String(describing: store.state.sessionEnd))")
            return
        }

        quarantine.release()
        await store.receive(\.sessionQuarantineFinished)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(quarantine.calls.value.count == 1)
        await end(store, environment)
    }
}
