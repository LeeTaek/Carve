//
//  ChapterCanvasOwnershipInjectionTesting.swift
//  CarveFeatureTest
//
//  ACC-1 2차의 DEBUG 소유 주입 — 주입 표식이 초안에 이어지고, 주입 없는 실행은 그것을 근거로 보지 않는다 (테스트 계획 §3-2, 10차 리뷰 결정 3).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 시험용으로 주입한 소유 근거가 주입 없는 실행으로 번져, 그 초안이 **그 계정의 것**처럼 이어 쓰이고 저장소(동기화)에 들어가는 것
/// - 주입 표식이 닫는 세션의 초안 · 이어 쓴 초안에서 사라지는 것(다음 실행이 근거를 가릴 수 없게 된다)
@Suite("절 초안 — 시험용 소유 주입")
@MainActor
struct ChapterCanvasOwnershipInjectionTesting: DraftTestSamples {
    private var verseOne: DraftVerse { DraftVerse(chapter: CanvasTestSupport.chapter, verse: 1) }

    /// 주입된 환경 — 확인된 계정에 소유 근거를 **가정**하고 그 사실을 표식으로 남긴다.
    private func injected(_ scope: AccountScope, _ generation: UInt64) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: generation),
            knowledge: EraseEpochKnowledge(), storeOwnership: scope, ownershipInjected: true
        )
    }

    @Test("주입한 세션은 저장소에 쓰고, 그 초안과 닫는 세션의 초안이 주입 표식을 든다")
    func injectedSessionWritesStoreAndMarksDrafts() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(injected(accountA, 1))
        let drafts = RecordingDraftStore()
        // 인계 시한을 흐르지 않게 둔다 — 시한이 지나면 닫지 않고 다시 요청한다(토큰이 바뀐다).
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("b")],
            environment: environment, drafts: drafts, clock: TestClock()
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        #expect(store.state.persistsToStore)

        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        let first = try #require(drafts.saves.value.first)
        #expect(first.ownershipInjected == true)
        #expect(first.storeOwnership == accountA)
        // 저장소로 갈 초안이므로 "보내는 중" 으로 남는다.
        #expect(first.storeState == .sending)

        // 계정이 바뀌어 세션을 닫는 동안 마지막 획이 들어온다 — 닫는 세션(주입된 A)의 초안이 된다.
        environment.change(to: injected(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.send(.editHandoffCompleted(token: store.state.handoffToken))

        let closing = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("create-b".utf8) })
        #expect(closing.ownershipInjected == true)
        #expect(closing.storeOwnership == accountA)
        #expect(drafts.stored(in: accountB).isEmpty)

        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    @Test("주입 없는 실행은 주입된 초안을 근거로 보지 않는다 — 보이기만 하고 이어 그려도 저장소에 쓰지 않는다")
    func injectedDraftIsNotEvidenceWithoutInjection() async throws {
        let spy = spyWithVerseOne()
        // 주입 없이 **실제로 소유가 확인된** 환경이어도 주입된 초안은 그 계정의 근거가 아니다.
        let environment = ControlledEditEnvironment(confirmed(accountA, 2))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft(storeOwnership: accountA, ownershipInjected: true)
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [replaceVerseOne("continued")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.persistsToStore)
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("earlier".utf8))
        #expect(store.state.drafts.inherited[verseOne] == earlier.provenance)
        #expect(!store.state.writesStore(verse: 1))

        await draw(store, "continued")
        await store.receive(\.draftsSaved)

        let continued = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("continued".utf8) })
        // 이어 쓴 초안도 주입 표식을 그대로 든다 — 다음 실행이 다시 가릴 수 있어야 한다.
        #expect(continued.ownershipInjected == true)
        #expect(continued.provenance == earlier.provenance)
        #expect(spy.applied.value.isEmpty)
        await end(store, environment)
    }

    @Test("주입한 실행에서는 그 초안을 지금 세션으로 이어 쓴다")
    func injectedDraftContinuesUnderInjection() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(injected(accountA, 2))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft(storeOwnership: accountA, ownershipInjected: true)
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [replaceVerseOne("continued")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("earlier".utf8))
        #expect(store.state.drafts.inherited[verseOne] == nil)
        #expect(store.state.writesStore(verse: 1))

        await draw(store, "continued")
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        let continued = try #require(drafts.stored(in: accountA).first { $0.lineData == Data("continued".utf8) })
        #expect(continued.ownershipInjected == true)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }
}
