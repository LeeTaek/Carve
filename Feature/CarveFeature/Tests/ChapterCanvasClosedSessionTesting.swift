//
//  ChapterCanvasClosedSessionTesting.swift
//  CarveFeatureTest
//
//  닫은 편집 세션의 문맥 — 캔버스가 새 세대를 표시할 때까지 두고, 연달아 바뀌어도 첫 세션의 늦은 보고를 받는다 (정책 §12-6 구현 순서 ②, 10차 리뷰 3).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 세션이 연달아 바뀌면(A → B → A) 첫 세션의 문맥이 두 번째 문맥에 밀려, 그 뒤에 온 첫 세션의 편집을 계산할 기준이 사라지는 것(조용한 유실)
/// - 늦은 보고가 더 올 수 없는데도 닫은 문맥을 계속 들고 있는 것
@Suite("편집 세션 — 닫은 문맥은 캔버스가 지날 때까지")
@MainActor
struct ChapterCanvasClosedSessionTesting: DraftTestSamples {

    @Test("두 번 연속 전환 뒤에 온 첫 세션의 늦은 편집도 그 세션의 초안이 되고, 캔버스가 새 세대를 표시하면 문맥을 놓는다")
    func lateEditSurvivesTwoTransitions() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let canvas = UUID(700)
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("late")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store, id: canvas)
        let firstGeneration = store.state.renderedRevision
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        let firstSession = try #require(store.state.drafts.sessionID)

        // A → B. 뷰는 인계를 마쳤지만 **새 세대를 표시했다고는 아직 알리지 않았다**(메인 스레드 지연 · 갱신 지연).
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.send(.editHandoffCompleted(token: store.state.handoffToken))
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(store.state.closedDrafts.contexts.map(\.generation).contains(firstGeneration))

        // B → A. 지킬 미저장분이 없어 곧바로 닫힌다 — 첫 세션의 문맥은 그대로 있어야 한다.
        environment.change(to: confirmed(accountA, 3))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.renderedRevision > firstGeneration)
        #expect(store.state.closedDrafts.contexts.map(\.generation).contains(firstGeneration))

        // 이제야 첫 세대의 편집이 보고된다.
        await store.send(.editEnded(CanvasTestSupport.edit("late", generation: firstGeneration)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)

        let late = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("create-late".utf8) })
        #expect(late.key.sessionID == firstSession)
        #expect(late.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(late.key.sessionID != store.state.drafts.sessionID)
        #expect(drafts.stored(in: accountB).isEmpty)
        // 늦은 편집은 지금 세션의 저장소 저장으로 가지 않았다 — 붙잡혀 있던 a 한 번뿐이다.
        #expect(spy.applied.value.count == 1)

        // 캔버스가 마침내 지금 세대를 표시했다 — 더 늦은 보고가 올 수 없으므로 닫은 문맥을 놓는다.
        await store.send(.canvasDisplayed(id: canvas, revision: store.state.renderedRevision))
        #expect(store.state.closedDrafts.contexts.isEmpty)
        #expect(store.state.closedDrafts.sessions.isEmpty)
        #expect(store.state.closedDrafts.pending.isEmpty)
        await end(store, environment)
    }

    @Test("캔버스가 아직 옛 세대를 표시하는 동안에는 닫은 문맥을 놓지 않는다")
    func closedContextIsKeptWhileCanvasShowsOldGeneration() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let canvas = UUID(701)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store, id: canvas)
        let firstGeneration = store.state.renderedRevision
        await draw(store)
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        // 저장까지 끝났으므로 지킬 미저장분이 없다 — 인계를 기다리지 않고 닫고 다시 읽는다.
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        // 캔버스는 아직 옛 세대를 표시하고 있다 — 그 세대의 보고가 아직 올 수 있으므로 문맥을 둔다.
        #expect(store.state.closedDrafts.contexts.map(\.generation) == [firstGeneration])

        // 캔버스가 떨어지면 떨어지며 마지막 보고를 마친 것이다 — 문맥을 놓는다.
        await store.send(.canvasDetached(id: canvas))
        #expect(store.state.closedDrafts.contexts.isEmpty)
        await end(store, environment)
    }
    /// 캔버스가 둘일 때다(화면 분할 · 뷰 재생성 직후). 하나가 새 세대를 표시해도 **다른 하나가 아직 옛 세대를 보고 있으면**
    /// 그 세대의 늦은 편집이 올 수 있다 — 문맥을 놓으면 그 편집을 계산할 기준이 사라진다(11차 리뷰 P1).
    @Test("캔버스 둘 가운데 하나만 새 세대를 표시하면 문맥을 두고, 남은 캔버스의 늦은 편집을 그 세션의 초안으로 남긴다")
    func crossedHandoffBetweenTwoCanvases() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let first = UUID(710)
        let second = UUID(711)
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("late")],
            environment: environment, drafts: drafts, clock: TestClock()
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store, id: first)
        await attachCanvas(store, id: second)
        let oldGeneration = store.state.renderedRevision
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        let closingSession = try #require(store.state.drafts.sessionID)

        // 계정이 바뀌어 세션을 닫는다. 인계는 마쳤다.
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.send(.editHandoffCompleted(token: store.state.handoffToken))
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)

        // 한 캔버스만 새 세대를 표시했다 — 다른 하나는 아직 옛 세대다.
        await store.send(.canvasDisplayed(id: first, revision: store.state.renderedRevision))
        #expect(store.state.closedDrafts.contexts.map(\.generation).contains(oldGeneration))

        // 남은 캔버스가 그 옛 세대의 편집을 이제 보고한다.
        await store.send(.editEnded(CanvasTestSupport.edit("late", generation: oldGeneration)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)

        let late = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("create-late".utf8) })
        #expect(late.key.sessionID == closingSession)
        #expect(drafts.stored(in: accountB).isEmpty)
        #expect(spy.applied.value.count == 1)

        // 남은 캔버스가 떨어지면(떨어지며 마지막 보고를 마친다) 더 올 보고가 없다 — 문맥을 놓는다.
        await store.send(.canvasDetached(id: second))
        #expect(store.state.closedDrafts.contexts.isEmpty)
        #expect(store.state.closedDrafts.pending.isEmpty)
        await end(store, environment)
    }

    /// 한 캔버스가 떨어져도 남은 캔버스가 옛 세대를 보고 있으면 문맥을 놓지 않는다.
    @Test("캔버스 하나가 떨어져도 남은 캔버스가 옛 세대면 닫은 문맥을 둔다")
    func detachOfOneCanvasKeepsContextForTheOther() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let first = UUID(712)
        let second = UUID(713)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store, id: first)
        await attachCanvas(store, id: second)
        let oldGeneration = store.state.renderedRevision
        await draw(store)
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        // 한 캔버스가 새 세대를 표시하고 떨어졌다. 남은 캔버스는 아직 옛 세대다.
        await store.send(.canvasDisplayed(id: first, revision: store.state.renderedRevision))
        await store.send(.canvasDetached(id: first))
        #expect(store.state.closedDrafts.contexts.map(\.generation) == [oldGeneration])
        #expect(store.state.hasCanvas)

        await store.send(.canvasDisplayed(id: second, revision: store.state.renderedRevision))
        #expect(store.state.closedDrafts.contexts.isEmpty)
        await end(store, environment)
    }

}
