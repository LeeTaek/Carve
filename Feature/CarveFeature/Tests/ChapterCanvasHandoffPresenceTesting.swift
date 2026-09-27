//
//  ChapterCanvasHandoffPresenceTesting.swift
//  CarveFeatureTest
//
//  세션을 닫을 때의 인계 — 응답 지연을 "캔버스 없음" 으로 보지 않고, 인계 뒤 늦게 온 편집은 옛 세션의 초안으로 남긴다 (정책 §12-6 구현 순서 ②).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 캔버스가 있는데 응답이 늦다고(긴 획 · 메인 스레드 지연 · 늦은 변경 보고) 받은 편집까지로 닫아, 그 뒤 보고된 획을 옛 세션 밖에 두는 것
/// - 캔버스가 없는데 오지 않을 응답을 기다리며 입력을 막아 두는 것
/// - 인계를 마친 뒤 늦게 온 옛 세대의 편집을 새 세션의 ID · 근거로 초안을 쓰고, 새 세션이 유효하면 저장소에 넣는 것(출처가 섞인다)
@Suite("편집 세션 — 캔버스 유무와 인계")
@MainActor
struct ChapterCanvasHandoffPresenceTesting: EditSessionTestHelpers {
    @Test("캔버스가 없으면 인계를 기다리지 않고 받은 편집까지로 곧바로 닫는다")
    func noCanvasClosesImmediately() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts, clock: clock)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        let tokenBefore = store.state.handoffToken

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)

        // 시계를 움직이지 않았다 — 기다린 시한 없이 닫혔다. 뷰에 인계를 요청하지도 않았다.
        #expect(store.state.sessionEnd == nil)
        #expect(store.state.handoffToken == tokenBefore)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-a".utf8)])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    /// 긴 획 — 뷰는 획이 끝나 반영될 때까지 인계를 마치지 않는다. 그동안 시한이 몇 번 지나도 닫지 않는다.
    @Test("캔버스가 있으면 시한이 지나도 닫지 않고 다시 요청하며, 긴 획이 끝나 뷰가 마치면 그 획까지 닫는 세션의 초안에 넣는다")
    func delayedResponseIsNotTreatedAsAbsence() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("long")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        // 긴 획을 긋는 중에 계정이 바뀐다.
        await store.send(.editBegan)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let first = store.state.handoffToken
        #expect(store.state.sessionEnd?.phase == .handingOff(token: first))
        for attempt in 1...2 {
            await clock.advance(by: ChapterCanvasFeature.sessionHandoffTimeout)
            await store.receive(\.sessionHandoffTimedOut)
            #expect(store.state.sessionEnd?.phase == .handingOff(token: first + attempt))
            #expect(!store.state.isInputEnabled)
        }

        // 획이 끝났다 — 뷰가 그 획을 보고하고 가장 최근 요청의 인계를 마친다.
        await store.send(.editEnded(CanvasTestSupport.edit("long")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.send(.editHandoffCompleted(token: first + 2))

        #expect(store.state.sessionEnd == nil)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-long".utf8)])
        #expect(drafts.stored(in: accountB).isEmpty)
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    @Test("인계를 기다리던 캔버스가 떨어지면 — 떨어지며 미보고 획을 먼저 보고한다 — 곧바로 닫는다")
    func detachDuringHandoffCloses() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("b")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store, id: UUID(7))
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd != nil)

        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.send(.canvasDetached(id: UUID(7)))

        #expect(store.state.sessionEnd == nil)
        #expect(!store.state.hasCanvas)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-b".utf8)])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    @Test("hold runtime 연결은 정확한 캔버스 인계 뒤에만 준비 완료하고, 취소 전까지 입력을 잠근다")
    func storeReconnectRequiresExactHandoffAndCanCancel() async throws {
        let environment = ControlledEditEnvironment(DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        ))
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: TestClock())
        await composeAndSubscribe(store, environment)
        #expect(store.state.editEnvironment.connectionHeld)
        await attachCanvas(store)

        let requestID = UUID(901)
        await store.send(.prepareForStoreReconnect(requestID))
        let token = store.state.storeReconnectHandoffToken
        #expect(token == store.state.handoffToken)
        #expect(!store.state.isInputEnabled)
        await store.send(.editHandoffCompleted(token: (token ?? 0) - 1))
        #expect(store.state.storeReconnectReadyID == nil)

        await store.send(.editHandoffCompleted(token: try #require(token)))
        await store.receive(.delegate(.storeReconnectReady(requestID)))
        #expect(store.state.storeReconnectReadyID == requestID)
        #expect(!store.state.isInputEnabled)
        await store.send(.cancelStoreReconnect(requestID))
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(store.state.isInputEnabled)
        await end(store, environment)
    }

    @Test("연결 준비 timeout은 완료 응답을 보내지 않고 입력을 복구하며 다음 요청을 허용한다")
    func storeReconnectTimeoutFailsAndCanRetry() async throws {
        let environment = ControlledEditEnvironment(DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        ))
        let clock = TestClock()
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: clock)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)

        let first = UUID(902)
        await store.send(.prepareForStoreReconnect(first))
        await clock.advance(by: ChapterCanvasFeature.storeReconnectTimeout)
        await store.receive(.storeReconnectTimedOut(first))
        await store.receive(.delegate(.storeReconnectFailed(first, "캔버스 편집 인계가 시간 안에 끝나지 않았습니다.")))
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(store.state.storeReconnectRequestID == nil)
        #expect(store.state.isInputEnabled)

        let retry = UUID(903)
        await store.send(.prepareForStoreReconnect(retry))
        #expect(store.state.storeReconnectRequestID == retry)
        await store.send(.cancelStoreReconnect(retry))
        await end(store, environment)
    }

    @Test("N-Canvas의 미사용 단일 Canvas는 실제 연결 보류를 다시 확인한 뒤에만 완료한다")
    func unusedCanvasReconnectChecksLiveHold() async {
        let held = DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        )
        let environment = ControlledEditEnvironment(held)
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: TestClock())
        let requestID = UUID(904)
        #expect(store.state.isUnusedForStoreReconnect)
        await store.send(.prepareForStoreReconnect(requestID))
        await store.receive(.storeReconnectEnvironmentChecked(requestID, held))
        await store.receive(.delegate(.storeReconnectReady(requestID)))
        #expect(store.state.storeReconnectReadyID == requestID)
        // 현재 편집 세션의 출처를 새 계정으로 덮지 않는다.
        #expect(store.state.editEnvironment == .unknown)
        await store.send(.cancelStoreReconnect(requestID))
        await end(store, environment)
    }

    @Test("미사용 Canvas라도 현재 runtime의 연결 보류가 아니면 완료하지 않는다")
    func unusedCanvasReconnectRejectsUnheldRuntime() async {
        let environment = ControlledEditEnvironment(.unknown)
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: TestClock())
        let requestID = UUID(905)
        await store.send(.prepareForStoreReconnect(requestID))
        await store.receive(.storeReconnectEnvironmentChecked(requestID, .unknown))
        await store.receive(.delegate(.storeReconnectFailed(requestID, "비활성 Canvas의 보류 상태를 확인하지 못했습니다.")))
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(store.state.storeReconnectRequestID == nil)
        await end(store, environment)
    }

    @Test("미사용 Canvas 지름길은 조회 중이거나 이전 편집·초안 상태가 있으면 닫힌다")
    func unusedCanvasReconnectExcludesStartedWork() {
        let initial = ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)
        #expect(initial.isUnusedForStoreReconnect)
        var loading = initial
        loading.loadRequestID = UUID(906)
        #expect(!loading.isUnusedForStoreReconnect)
        var editing = initial
        editing.isEditing = true
        #expect(!editing.isUnusedForStoreReconnect)
        var previous = initial
        previous.editRevision = 1
        #expect(!previous.isUnusedForStoreReconnect)
        var draft = initial
        draft.drafts.sessionID = "preserved-session"
        #expect(!draft.isUnusedForStoreReconnect)
    }

    @Test("요청을 뷰가 받기 전에 마지막 Canvas가 떨어져도 선보고 계약으로 인계를 마친다")
    func storeReconnectLastDetachCompletesHandoff() async {
        let environment = ControlledEditEnvironment(DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        ))
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: TestClock())
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        let requestID = UUID(907)
        await store.send(.prepareForStoreReconnect(requestID))
        #expect(store.state.storeReconnectHandoffToken != nil)
        await store.send(.editCancelled)
        await store.send(.canvasDetached(id: UUID(700)))
        await store.receive(.delegate(.storeReconnectReady(requestID)))
        #expect(store.state.storeReconnectHandoffToken == nil)
        #expect(store.state.storeReconnectReadyID == requestID)
        await store.send(.cancelStoreReconnect(requestID))
        await end(store, environment)
    }

    @Test("연결 인계를 끝내도 실제 초안 저장을 기다리며, 저장 실패는 큐를 남기고 연결을 취소한다", arguments: [false, true])
    func storeReconnectWaitsForDraftOutcome(fails: Bool) async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        ))
        let drafts = RecordingDraftStore()
        drafts.failures.setValue(fails ? 1 : 0)
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("draft")],
            environment: environment, drafts: drafts, clock: TestClock()
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await editWithHeldDraft(store, drafts, tag: "draft")
        #expect(store.state.isSavingDrafts)
        #expect(store.state.hasUnsavedPending)
        let requestID = UUID(908)
        await store.send(.prepareForStoreReconnect(requestID))
        await store.send(.editHandoffCompleted(token: try #require(store.state.storeReconnectHandoffToken)))
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(!store.state.isInputEnabled)
        #expect(drafts.saves.value.isEmpty)
        #expect(spy.applied.value.isEmpty)

        drafts.release()
        await store.receive(\.draftsSaved)
        if fails {
            await store.receive(.delegate(.storeReconnectFailed(requestID, "로컬 초안을 저장하지 못했습니다. 필기는 화면과 대기열에 남아 있습니다.")))
            #expect(store.state.storeReconnectReadyID == nil)
            #expect(store.state.hasUnsavedPending)
            #expect(!store.state.pendingMutations.isEmpty)
            #expect(store.state.isInputEnabled)
            #expect(drafts.saves.value.isEmpty)
        } else {
            await store.receive(.delegate(.storeReconnectReady(requestID)))
            #expect(!store.state.hasUnsavedPending)
            #expect(drafts.saves.value.map(\.lineData) == [Data("create-draft".utf8)])
            #expect(!store.state.isInputEnabled)
            await store.send(.cancelStoreReconnect(requestID))
        }
        #expect(spy.applied.value.isEmpty)
        await end(store, environment)
    }

    @Test("소유가 확인된 저장 진행 중에는 hold 재연결을 거절하고 진행 중인 저장을 취소하지 않는다")
    func storeReconnectRejectsActiveStoreSaveWithoutCancellingIt() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("saving")],
            environment: environment, drafts: drafts, clock: TestClock()
        )
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy, tag: "saving")
        await store.receive(\.draftsSaved)
        guard case .saving = store.state.saveStatus else {
            Issue.record("실제 저장을 붙잡지 못했습니다.")
            spy.releaseApply()
            await end(store, environment)
            return
        }
        let pending = store.state.pendingMutations
        let requestID = UUID(909)
        await store.send(.prepareForStoreReconnect(requestID))
        await store.receive(.delegate(.storeReconnectFailed(requestID, "이 Canvas는 소유 확인 보류 상태가 아닙니다.")))
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(store.state.pendingMutations == pending)
        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.saveStatus == .idle)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    @Test("취소한 연결 요청의 늦은 ACK는 새 요청의 완료로 쓰지 않는다")
    func storeReconnectIgnoresCancelledRequestAck() async throws {
        let environment = ControlledEditEnvironment(DrawingEditEnvironment(
            accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge(), connectionHeld: true
        ))
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore(), clock: TestClock())
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        let first = UUID(910)
        await store.send(.prepareForStoreReconnect(first))
        let oldToken = try #require(store.state.storeReconnectHandoffToken)
        await store.send(.cancelStoreReconnect(first))
        let second = UUID(911)
        await store.send(.prepareForStoreReconnect(second))
        let currentToken = try #require(store.state.storeReconnectHandoffToken)
        #expect(currentToken != oldToken)
        await store.send(.editHandoffCompleted(token: oldToken))
        #expect(store.state.storeReconnectRequestID == second)
        #expect(store.state.storeReconnectReadyID == nil)
        #expect(store.state.storeReconnectHandoffToken == currentToken)
        await store.send(.editHandoffCompleted(token: currentToken))
        await store.receive(.delegate(.storeReconnectReady(second)))
        await store.send(.cancelStoreReconnect(second))
        await end(store, environment)
    }

    /// 인계는 요청 전까지의 편집을 보고받는 약속이다. 그래도 늦게 온 것은 옛 세션의 것이다 — 새 세션(B, 저장소에 쓰는 유효 세션)에 섞지 않는다.
    @Test("인계를 마친 뒤 도착한 옛 세대의 편집은 옛 세션 출처의 초안으로 남고, 저장소 · 새 세션에 섞지 않는다")
    func lateEditAfterHandoffStaysInClosedSession() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("late")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        let oldGeneration = store.state.renderedRevision
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        let closingSession = try #require(store.state.drafts.sessionID)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.send(.editHandoffCompleted(token: store.state.handoffToken))
        #expect(store.state.sessionEnd == nil)
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(store.state.persistsToStore)
        #expect(store.state.renderedRevision > oldGeneration)

        await store.send(.editEnded(CanvasTestSupport.edit("late", generation: oldGeneration)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)

        let late = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("create-late".utf8) })
        #expect(late.key.sessionID == closingSession)
        #expect(late.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(late.storeOwnership == accountA)
        #expect(drafts.stored(in: accountB).isEmpty)
        // 붙잡혀 있던 a 한 번뿐 — 늦은 편집은 B 세션의 저장소 저장으로 가지 않았다.
        #expect(spy.applied.value.count == 1)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.closedDrafts.pending.isEmpty)
        #expect(store.state.drafts.sessionID == nil)
        await end(store, environment)
    }

    /// 팔레트 되돌리기도 편집 구간을 연다(`editBegan`). 그 사이 세션을 닫으면 뷰가 되돌린 결과를 보고한 뒤에 마친다.
    @Test("되돌리기 중에 세션을 닫으면 되돌린 결과까지 닫는 세션의 초안에 넣고, 닫는 동안 되돌리기 · 다시 하기 요청은 받지 않는다")
    func undoDuringHandoffJoinsClosingSession() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("undone")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        await store.send(.undoStateChanged(canUndo: true, canRedo: true))
        await store.send(.editBegan)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let token = store.state.handoffToken
        let undoBefore = store.state.undoRequestVersion
        let redoBefore = store.state.redoRequestVersion
        await store.send(.undoTapped)
        await store.send(.redoTapped)
        #expect(store.state.undoRequestVersion == undoBefore)
        #expect(store.state.redoRequestVersion == redoBefore)

        await store.send(.editEnded(CanvasTestSupport.edit("undone", reason: .undo)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.send(.editHandoffCompleted(token: token))

        #expect(store.state.sessionEnd == nil)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-undone".utf8)])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    /// 비활성화되면 시한이 돌지 않을 수 있다 — 기다리지 않고 지금 다시 요청해, 멈추기 전에 마지막 획을 받는다.
    @Test("인계를 기다리는 중에 백그라운드로 가면(저장 요청) 닫지 않고 지금 다시 요청한다")
    func backgroundDuringHandoffRequestsAgain() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts, clock: clock)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let first = store.state.handoffToken

        await store.send(.flushPending)
        #expect(store.state.sessionEnd?.phase == .handingOff(token: first + 1))
        #expect(!store.state.isInputEnabled)

        // 앞선 요청의 응답은 받지 않는다. 다시 요청한 인계의 응답으로 닫는다.
        await store.send(.editHandoffCompleted(token: first))
        #expect(store.state.sessionEnd != nil)
        await store.send(.editHandoffCompleted(token: first + 1))
        #expect(store.state.sessionEnd == nil)
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }
}
