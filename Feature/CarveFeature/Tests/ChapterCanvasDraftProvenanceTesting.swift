//
//  ChapterCanvasDraftProvenanceTesting.swift
//  CarveFeatureTest
//
//  복구한 초안의 출처 — 보이기만 하는 초안에 획을 더해도 귀속이 올라가지 않는다 (정책 §12-6 구현 순서 ②).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 보존만 · 확인 대기 초안을 이어 보인 절에 한 획을 더한 것을 계정 간 가져오기 동의로 보는 것 — 새 초안이 지금 세션의 계정 · K ·
///   소유 근거를 들고, 원 초안이 출처를 잃은 채 지워지고, 유효 세션이면 저장소(동기화)에 쓰인다
/// - 확인 대기 중 이어 그린 필기가 다른 계정으로 확인된 뒤 그 계정에 붙는 것
/// - 처음부터 미확인이던 초안의 미확인 근거가 이어 그리기로 지워지는 것
/// - 로그인하지 않은 채 쓴 필기를 저장소에 넣는 것 — 미러링이 다음에 로그인한 계정으로 올린다(ACC-1 F30)
@Suite("절 초안 — 복구한 초안의 출처")
@MainActor
struct ChapterCanvasDraftProvenanceTesting: DraftTestSamples {
    private var verseOne: DraftVerse { DraftVerse(chapter: CanvasTestSupport.chapter, verse: 1) }

    @Test("보존만 초안을 이어 보인 뒤 소유가 확인된 유효 세션에서 한 획을 더해도 원 초안의 출처를 잇고 저장소에 쓰지 않는다 — 다른 절은 쓴다")
    func showOnlyDraftKeepsProvenanceInValidSession() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft()
        drafts.seed(earlier)
        let store = makeStore(
            spy: spy, results: [replaceVerseOne("continued"), CanvasTestSupport.createResult("fresh")], environment: environment, drafts: drafts
        )
        await composeAndSubscribe(store, environment)
        #expect(store.state.persistsToStore)
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("earlier".utf8))
        #expect(store.state.drafts.inherited[verseOne] == earlier.provenance)
        // 그 절은 저장소 행을 바꾸는 메뉴도 띄우지 않는다.
        #expect(!store.state.writesStore(verse: 1))
        #expect(store.state.writesStore(verse: 2))

        await draw(store, "continued")
        await store.receive(\.draftsSaved)

        let continued = try #require(drafts.stored(in: accountA).first { $0.key.verse == 1 })
        // (1) 원 초안의 출처 · 기준을 그대로 잇는다 — 지금 세션의 표 · 소유 근거로 바꾸지 않는다.
        #expect(continued.provenance == earlier.provenance)
        #expect(continued.storeOwnership == nil)
        #expect(continued.baseFingerprint == storedVerseOneFingerprint)
        #expect(continued.lineData == Data("continued".utf8))
        // (2) 저장소에 쓰지 않는다 — 초안이 곧 보존이라 큐에서 내렸다.
        #expect(spy.applied.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        // (3) 출처가 그대로 이어졌으므로 원 초안을 대신한다.
        #expect(drafts.removed.value == [earlier.key])

        // 이 세션의 다른 절은 저장소에 쓴다.
        await draw(store, "fresh")
        await store.receive(\.saveFinished)
        #expect(spy.applied.value.count == 1)
        #expect(spy.applied.value.first?.mutations.map(\.verse) == [2])
        #expect(store.state.drafts.inherited[verseOne] == earlier.provenance)
        await end(store, environment)
    }

    @Test("근거가 유효한 다른 세션의 초안은 지금 세션으로 이어 쓰고 저장소에도 쓴다")
    func validDraftIsAdoptedIntoSession() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft(storeOwnership: accountA)
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [replaceVerseOne("continued")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(store.state.drafts.adopted[verseOne] == earlier.ref)
        #expect(store.state.drafts.inherited[verseOne] == nil)

        await draw(store, "continued")
        await store.receive(\.saveFinished)
        #expect(spy.applied.value.first?.mutations.map(\.verse) == [1])
        // 초안 저장과 저장소 저장은 함께 돈다 — 둘 다 끝난 뒤에 본다.
        await end(store, environment)

        let continued = try #require(drafts.stored(in: accountA).first)
        #expect(continued.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(continued.storeOwnership == accountA)
        #expect(drafts.removed.value == [earlier.key])
    }

    @Test("확인 대기 중 이어 그린 필기는 A 세션의 초안으로 남고, B 로 확인된 뒤 B 에 붙지 않는다")
    func awaitingDraftDoesNotAttachToNextAccount() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        environment.change(to: DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                      knowledge: EraseEpochKnowledge()))
        await store.receive(\.editEnvironmentChanged)
        await draw(store)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        let kept = try #require(drafts.stored(in: accountA).first)
        #expect(kept.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(kept.storeOwnership == accountA)
        #expect(drafts.stored(in: accountB).isEmpty)
        #expect(spy.applied.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        // B 세션은 그 필기를 보이지도 이어받지도 않는다.
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 } == false)
        #expect(store.state.drafts.adopted.isEmpty)
        #expect(store.state.drafts.inherited.isEmpty)
        await end(store, environment)
    }

    /// 확인 전 초안은 "계정 미확인" 묶음에 남는다. 이어 그려도 그 근거(당시의 마지막 확인 힌트까지)를 지금 환경의 것으로 바꾸지 않는다.
    @Test("처음부터 미확인이던 초안을 이어 그려도 그 미확인 근거가 남고, 그 계정으로 확인돼도 보이기만 한다")
    func unverifiedDraftKeepsItsBasis() async throws {
        let spy = spyWithVerseOne()
        let unverified = DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: nil), serverWork: nil,
                                                knowledge: EraseEpochKnowledge())
        let environment = ControlledEditEnvironment(unverified)
        let drafts = RecordingDraftStore()
        let earlier = previousDraft(account: .unverified(hint: accountA))
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [replaceVerseOne("continued")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(store.state.drafts.inherited[verseOne]?.account == .unverified(hint: accountA))

        await draw(store, "continued")
        await store.receive(\.draftsSaved)
        let continued = try #require(drafts.stored(in: .unverified).first)
        // 지금 환경의 힌트(없음)가 아니라 원 초안의 근거다.
        #expect(continued.account == .unverified(hint: accountA))
        #expect(continued.lineData == Data("continued".utf8))

        environment.change(to: confirmed(accountA, 1))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        #expect(drafts.stored(in: accountA).isEmpty)
        #expect(drafts.stored(in: .unverified).map(\.account) == [.unverified(hint: accountA)])
        // 확인된 계정이 그 초안이 참고하던 계정과 같다 — 이어 보이되 **보이기만** 하고, 묶음 · 출처 · 저장소는 그대로다(사용자 결정 2026-09-21).
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("continued".utf8))
        #expect(store.state.drafts.inherited[verseOne]?.account == .unverified(hint: accountA))
        #expect(!store.state.writesStore(verse: 1))
        #expect(spy.applied.value.isEmpty)
        await end(store, environment)
    }

    /// 로그인하지 않은 세션은 이 기기 전용 문맥으로는 유효하다. 그래도 미러링은 그 행을 다음에 로그인한 계정으로 올린다(ACC-1 F30).
    @Test("로그인하지 않은 세션은 저장소에 쓰지 않고 이 기기 전용 초안에만 남긴다")
    func signedOutSessionDoesNotWriteStore() async throws {
        let spy = RepositorySpy()
        let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
        let environment = ControlledEditEnvironment(signedOut)
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(store.state.sessionValidity == .valid)
        #expect(!store.state.persistsToStore)

        await draw(store)
        await store.receive(\.draftsSaved)

        #expect(spy.applied.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.localSaveIndicator == .saved)
        let saved = try #require(drafts.stored(in: .localOnly).first)
        #expect(saved.account == .localOnly)
        #expect(!store.state.writesStore(verse: 2))
        await end(store, environment)
    }
    // MARK: - 확인 전 묶음 (ACC-1 2차 ④ · 사용자 결정 2026-09-21)

    @Test("확인 전에 쓴 초안은 그때 참고하던 계정으로 확인되면 보이기만 하고, 이어 그려도 그 묶음 · 출처에 남는다")
    func unverifiedDraftIsCarriedIntoMatchingAccount() async throws {
        let spy = spyWithVerseOne()
        let drafts = RecordingDraftStore()
        let carried = previousDraft(session: "unverified-session", ink: "확인 전", account: .unverified(hint: accountA))
        drafts.seed(carried)
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let store = makeStore(spy: spy, results: [replaceVerseOne("이어")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("확인 전".utf8))
        #expect(store.state.drafts.inherited[verseOne] == carried.provenance)
        #expect(!store.state.writesStore(verse: 1))

        await draw(store, "이어")
        await store.receive(\.draftsSaved)

        let continued = try #require(drafts.stored(in: .unverified).first { $0.lineData == Data("이어".utf8) })
        #expect(continued.account == .unverified(hint: accountA))
        #expect(spy.applied.value.isEmpty)
        #expect(drafts.stored(in: accountA).isEmpty)
        await end(store, environment)
    }

    @Test("확인 전 초안의 힌트가 다른 계정이면 그 계정 화면에 보이지 않는다 — 파일은 남는다")
    func unverifiedDraftWithOtherHintIsNotShown() async throws {
        let spy = spyWithVerseOne()
        let drafts = RecordingDraftStore()
        let other = previousDraft(session: "unverified-other", ink: "다른 계정 참고", account: .unverified(hint: accountB))
        drafts.seed(other)
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data([1]))
        #expect(store.state.drafts.inherited[verseOne] == nil)
        #expect(drafts.stored(in: .unverified) == [other])
        await end(store, environment)
    }

}
