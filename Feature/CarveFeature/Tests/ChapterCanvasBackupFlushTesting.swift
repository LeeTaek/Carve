//
//  ChapterCanvasBackupFlushTesting.swift
//  CarveFeatureTest
//
//  백업 전 flush 완료 신호 — 열린 필사 화면의 마지막 편집이 이 기기에 내구성 있게 남았는지 요청마다 한 번 답한다
//  (docs/backup-import-design.md §5-2 · 정책 §6-1 1단계). 인계 · 초안 · 저장은 편집 세션 시험의 대역으로, 시한은 TestClock 으로 본다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 부모가 받은 백업 전 flush 답 하나.
private struct FlushAnswer: Equatable, Sendable {
    let id: UUID
    let outcome: CanvasFlushOutcome
}

/// 시험의 요청 id.
private let firstRequest = UUID(901)
private let secondRequest = UUID(902)

/// 편집 세션 시험과 같은 대역에, 부모가 받는 백업 전 flush 답을 모두 적는 리듀서를 덧붙인다 — 비망라 TestStore 는 확인하지 않은 액션을
/// 말없이 넘기므로, 같은 요청에 두 번 · 다른 요청에 답하지 않았는지는 이 기록으로 끝까지 본다.
@MainActor
private func makeFlushStore(
    spy: RepositorySpy,
    results: [DrawingEditResult] = [],
    environment: ControlledEditEnvironment,
    drafts: RecordingDraftStore,
    clock: TestClock<Duration>,
    answers: LockIsolated<[FlushAnswer]>
) -> TestStoreOf<ChapterCanvasFeature> {
    let store = TestStore(initialState: ChapterCanvasFeature.State(page: CanvasTestSupport.page)) {
        // TestStore 의 reducer 인자는 결과 빌더가 아니다 — 둘을 묶는다.
        CombineReducers {
            ChapterCanvasFeature()
            Reduce<ChapterCanvasFeature.State, ChapterCanvasFeature.Action> { _, action in
                if case let .delegate(.backupFlushFinished(id, outcome)) = action {
                    answers.withValue { $0.append(FlushAnswer(id: id, outcome: outcome)) }
                }
                return .none
            }
        }
    } withDependencies: {
        $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results))
        $0.drawingRepository = spy
        $0.uuid = .incrementing
        $0.date = .constant(Date(timeIntervalSince1970: 1_000))
        $0.drawingEditEnvironment = environment
        $0.verseDraftStore = drafts
        $0.continuousClock = clock
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
}

/// 이 스위트가 막는 것:
/// - 요청을 보내기만 하고 답해, 디바운스 안의 마지막 획 · 초안 · 저장소 저장이 끝나기 전에 백업이 시작되는 것
/// - 지킬 편집이 없는데(캔버스가 없는데) 오지 않을 인계를 기다리며 답을 미루는 것
@Suite("백업 전 flush — 마지막 편집이 이 기기에 남은 뒤에 durable 로 답한다")
@MainActor
struct ChapterCanvasBackupFlushTesting: EditSessionTestHelpers {
    @Test("지킬 편집이 없으면 캔버스가 있어도 인계를 기다리지 않고 곧바로 durable 로 답한다")
    func nothingUnsavedIsDurableAtOnce() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), clock: clock, answers: answers)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        #expect(!store.state.hasUnsavedChanges)
        let token = store.state.handoffToken

        await store.send(.backupFlushRequested(id: firstRequest))
        // `flushPending` 처럼 뷰에 인계는 요청하지만 응답을 기다리지 않는다 — 긋는 중 · 디바운스 안의 획이 있었다면 `isEditing` 이 잡았다.
        #expect(store.state.handoffToken == token + 1)
        #expect(store.state.backupFlush?.outcome == .durable)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .durable)))

        // 시한을 걸지 않았다 — 시간이 지나도, 그 인계의 응답이 와도 다시 답하지 않는다.
        await clock.advance(by: ChapterCanvasFeature.backupFlushTimeout)
        await store.send(.editHandoffCompleted(token: token + 1))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .durable)])
    }

    @Test("캔버스가 없으면 인계를 기다리지 않는다 — 지킬 편집이 없으면 곧바로, 도는 저장이 있으면 그것이 끝나면 durable")
    func noCanvasDoesNotWaitForHandoff() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: RecordingDraftStore(),
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        #expect(!store.state.hasCanvas)

        // 지킬 것이 없다.
        await store.send(.backupFlushRequested(id: firstRequest))
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .durable)))

        // 초안은 남았고 저장소 저장이 도는 중이다 — 저장소로 갈 것은 저장소까지 기다린다. 인계는 기다리지 않는다(떨어질 때 보고를 마쳤다).
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        #expect(store.state.hasUnsavedChanges)
        await store.send(.backupFlushRequested(id: secondRequest))
        #expect(store.state.backupFlush?.isHandedOff == true)
        #expect(store.state.backupFlush?.isWaiting == true)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(.delegate(.backupFlushFinished(id: secondRequest, outcome: .durable)))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .durable), FlushAnswer(id: secondRequest, outcome: .durable)])
        #expect(spy.applied.value.count == 1)
    }

    @Test("디바운스 안의 마지막 획 — 인계로 들어온 그 획이 초안과 저장소에 닿은 뒤에야 durable 로 답한다")
    func lastStrokeIsDurableAfterDraftAndStore() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("last")], environment: environment, drafts: drafts,
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        #expect(store.state.persistsToStore)

        // 마지막 획을 긋고 펜을 뗐다 — 뷰가 아직 보고하지 않았다(디바운스 안).
        await store.send(.editBegan)
        await store.send(.backupFlushRequested(id: firstRequest))
        let token = store.state.handoffToken
        #expect(store.state.backupFlush?.isHandedOff == false)

        // 뷰가 인계에 답한다 — 그 획을 먼저 보고하고 인계를 마친다. 초안 · 저장소 저장은 붙잡아 둔다.
        drafts.holdNextSave()
        spy.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("last")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: token))
        #expect(store.state.backupFlush?.isHandedOff == true)
        #expect(store.state.backupFlush?.isWaiting == true)

        drafts.release()
        await store.receive(\.draftsSaved)
        // 초안은 남았다 — 저장소로 갈 것은 저장소까지 기다린다.
        #expect(store.state.backupFlush?.isWaiting == true)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .durable)))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .durable)])
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-last".utf8)])
        #expect(spy.applied.value.map(\.mutations) == [CanvasTestSupport.createResult("last").mutations])
    }

    @Test("초안만 남기는 세션(저장소 소유 근거 없음)은 인계로 들어온 마지막 획이 초안이 되면 durable — 저장소에는 쓰지 않는다")
    func preserveOnlySessionIsDurableOnceDrafted() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("last")], environment: environment, drafts: drafts,
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        #expect(!store.state.persistsToStore)

        await store.send(.editBegan)
        await store.send(.backupFlushRequested(id: firstRequest))
        let token = store.state.handoffToken

        drafts.holdNextSave()
        await store.send(.editEnded(CanvasTestSupport.edit("last")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: token))
        // 인계는 끝났지만 그 획이 아직 초안이 되지 않았다.
        #expect(store.state.backupFlush?.isWaiting == true)

        drafts.release()
        await store.receive(\.draftsSaved)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .durable)))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .durable)])
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-last".utf8)])
        #expect(spy.applied.value.isEmpty)
    }

    @Test("세션을 닫는 중이면 flushPending 의 재시도처럼 닫기의 인계를 다시 요청하고, 그 획이 닫는 세션의 초안이 되면 durable")
    func closingSessionRetriesHandoffLikeFlushPending() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("closing")], environment: environment, drafts: drafts,
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)

        // 획을 긋는 중에 계정이 바뀐다 — 세션을 닫기 시작하고 뷰에 인계를 요청한다.
        await store.send(.editBegan)
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let closingToken = store.state.handoffToken
        #expect(store.state.sessionEnd?.phase == .handingOff(token: closingToken))

        await store.send(.backupFlushRequested(id: firstRequest))
        // `flushPending` 의 재시도와 같다 — 닫기의 인계를 다시 요청하고, 그 응답을 기다린다.
        #expect(store.state.sessionEnd?.phase == .handingOff(token: closingToken + 1))
        #expect(store.state.backupFlush?.handoffToken == closingToken + 1)
        #expect(store.state.backupFlush?.isHandedOff == false)

        drafts.holdNextSave()
        await store.send(.editEnded(CanvasTestSupport.edit("closing")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: closingToken + 1))
        // 인계는 끝났지만 그 획이 아직 닫는 세션의 초안이 되지 않았다.
        #expect(store.state.backupFlush?.isWaiting == true)

        drafts.release()
        await store.receive(\.draftsSaved)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .durable)))
        #expect(store.state.sessionEnd == nil)
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .durable)])
        // 그 획은 닫는 세션(계정 A)의 초안으로 남았다. 저장소에는 쓰지 않았다.
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-closing".utf8)])
        #expect(drafts.stored(in: accountB).isEmpty)
        #expect(spy.applied.value.isEmpty)
    }
}

/// 이 스위트가 막는 것:
/// - 초안 · 저장소 저장에 실패했는데 durable 로 답하는 것, 정해지지 않은 채 답을 미루기만 하는 것(5초 시한)
/// - 같은 요청에 두 번 답하거나, 앞 요청의 늦은 인계 · 시한이 다른 요청에 답하는 것
@Suite("백업 전 flush — 실패 · 시한 · 요청마다 한 번")
@MainActor
struct ChapterCanvasBackupFlushOutcomeTesting: EditSessionTestHelpers {
    @Test("인계로 들어온 마지막 획을 초안으로 남기지 못하면 failed(retryCount:) 로 답한다 — 저장소 저장으로 대신하지 않는다")
    func draftFailureIsFailed() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        drafts.failures.setValue(1)
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("last")], environment: environment, drafts: drafts,
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)

        await store.send(.editBegan)
        await store.send(.backupFlushRequested(id: firstRequest))
        let token = store.state.handoffToken

        drafts.holdNextSave()
        await store.send(.editEnded(CanvasTestSupport.edit("last")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: token))
        #expect(store.state.backupFlush?.isWaiting == true)

        drafts.release()
        await store.receive(\.draftsSaved)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .failed(retryCount: 1))))
        #expect(store.state.saveRetryCount == 1)
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .failed(retryCount: 1))])
        #expect(spy.applied.value.isEmpty)
    }

    @Test("저장소 저장에 실패해 있던 미저장분은 요청이 다시 저장을 시도하고, 또 실패하면 failed(retryCount:) 로 답한다")
    func storeFailureIsRetriedThenFailed() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("disk"), .persistenceFailed("disk")])
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: RecordingDraftStore(),
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 1)

        // 요청은 `flushPending` 처럼 실패했던 저장을 다시 시도한다 — 다시 시도하는 동안에는 실패로 답하지 않는다.
        spy.holdNextApply()
        await store.send(.backupFlushRequested(id: firstRequest))
        #expect(store.state.saveRetryCount == nil)
        await store.send(.editHandoffCompleted(token: store.state.handoffToken))
        #expect(store.state.backupFlush?.isHandedOff == true)
        #expect(store.state.backupFlush?.isWaiting == true)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .failed(retryCount: 2))))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .failed(retryCount: 2))])
        #expect(spy.applied.value.count == 2)
    }

    @Test("뷰가 5초 안에 인계에 답하지 않으면 timedOut 으로 답하고, 그 뒤 늦게 온 인계 · 저장 결과로 다시 답하지 않는다")
    func unansweredHandoffTimesOut() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("late")], environment: environment, drafts: RecordingDraftStore(),
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)

        // 긴 획을 긋는 중이다 — 뷰는 그 획이 끝나야 인계를 마친다.
        await store.send(.editBegan)
        await store.send(.backupFlushRequested(id: firstRequest))
        let token = store.state.handoffToken
        await clock.advance(by: ChapterCanvasFeature.backupFlushTimeout - .milliseconds(1))
        #expect(answers.value.isEmpty)

        await clock.advance(by: .milliseconds(1))
        await store.receive(\.backupFlushTimedOut)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .timedOut)))

        // 이제야 획이 끝나 뷰가 보고하고 인계를 마친다 — 같은 요청에 다시 답하지 않는다.
        await store.send(.editEnded(CanvasTestSupport.edit("late")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: token))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .timedOut)])
        // 판정이 끝났을 뿐 저장 규칙은 그대로다 — 늦은 획도 저장한다.
        #expect(spy.applied.value.count == 1)
    }

    @Test("앞 요청의 늦은 인계 응답 · 시한 알림은 새 요청에 답하지 않는다 — 새 요청은 자기 인계를 기다린다")
    func lateResultsDoNotAnswerAnotherRequest() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("late")], environment: environment, drafts: RecordingDraftStore(),
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await store.send(.editBegan)

        await store.send(.backupFlushRequested(id: firstRequest))
        let firstToken = store.state.handoffToken
        await clock.advance(by: ChapterCanvasFeature.backupFlushTimeout)
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .timedOut)))

        // 다시 시도 — 새 요청은 새 인계를 요청한다.
        await store.send(.backupFlushRequested(id: secondRequest))
        let secondToken = store.state.handoffToken
        #expect(secondToken == firstToken + 1)

        // 앞 요청의 인계 응답과 시한 알림이 늦게 온다 — 새 요청의 인계가 아니므로 답하지 않는다.
        await store.send(.editHandoffCompleted(token: firstToken))
        #expect(store.state.backupFlush?.id == secondRequest)
        #expect(store.state.backupFlush?.isHandedOff == false)
        await store.send(.backupFlushTimedOut(id: firstRequest))
        #expect(store.state.backupFlush?.isWaiting == true)

        // 획이 끝나 뷰가 새 요청의 인계를 마친다.
        await store.send(.editEnded(CanvasTestSupport.edit("late")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: secondToken))
        await store.receive(.delegate(.backupFlushFinished(id: secondRequest, outcome: .durable)))
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .timedOut), FlushAnswer(id: secondRequest, outcome: .durable)])
    }

    @Test("같은 요청이 다시 와도 한 번만 답하고, 기다리는 중에 새 요청이 오면 앞 요청은 timedOut 으로 끝낸다")
    func eachRequestIsAnsweredOnce() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let clock = TestClock()
        let answers = LockIsolated<[FlushAnswer]>([])
        let store = makeFlushStore(
            spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: RecordingDraftStore(),
            clock: clock, answers: answers
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await store.send(.editBegan)

        await store.send(.backupFlushRequested(id: firstRequest))
        let token = store.state.handoffToken
        // 같은 요청이 또 왔다 — 인계를 다시 요청하지도, 답하지도 않는다.
        await store.send(.backupFlushRequested(id: firstRequest))
        #expect(store.state.handoffToken == token)
        #expect(store.state.backupFlush?.isWaiting == true)

        // 기다리는 중에 새 요청이 왔다 — 앞 요청은 정해지지 않은 채 끝내고 새로 기다린다.
        await store.send(.backupFlushRequested(id: secondRequest))
        await store.receive(.delegate(.backupFlushFinished(id: firstRequest, outcome: .timedOut)))
        #expect(store.state.backupFlush?.id == secondRequest)
        let secondToken = store.state.handoffToken

        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.send(.editHandoffCompleted(token: secondToken))
        await store.receive(.delegate(.backupFlushFinished(id: secondRequest, outcome: .durable)))

        // 답한 요청이 다시 와도, 시간이 지나도 더 답하지 않는다.
        await store.send(.backupFlushRequested(id: secondRequest))
        await clock.advance(by: ChapterCanvasFeature.backupFlushTimeout)
        await end(store, environment)
        #expect(answers.value == [FlushAnswer(id: firstRequest, outcome: .timedOut), FlushAnswer(id: secondRequest, outcome: .durable)])
    }
}
