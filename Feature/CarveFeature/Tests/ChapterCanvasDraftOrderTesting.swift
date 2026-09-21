//
//  ChapterCanvasDraftOrderTesting.swift
//  CarveFeatureTest
//
//  초안이 먼저, 저장소는 그 뒤 — 그리고 "들어감" 표식을 남기기 전에 끝난 초안 (정책 §12-6 구현 순서 ②, 10차 리뷰 2 · 4).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 초안이 남기 전에(또는 초안 저장이 실패한 채로) 저장소에 먼저 써서, 그 순간 앱이 끝나고 계정이 바뀌면 사본이 어디에도 없게 되는 것(ACC-1 F29)
/// - 저장소 저장을 마친 뒤 표식을 남기기 전에 끝났을 때, 다음 실행이 그 초안을 "들어갔다" 또는 "안 들어갔다" 로 단정해 지운 필기를 되살리는 것
/// - 기존 필기를 고친 초안이 계정 전환으로 행을 잃었을 때 화면에서 닿지 못하는 것(기준 행이 함께 사라진다)
@Suite("절 초안 — 초안이 먼저, 저장소는 뒤")
@MainActor
struct ChapterCanvasDraftOrderTesting: DraftTestSamples {

    private var place: DraftVerse { DraftVerse(chapter: CanvasTestSupport.chapter, verse: 1) }

    @Test("초안이 남기 전에는 저장소에 쓰지 않는다 — 초안이 남은 뒤에 보내고, 저장을 마치면 표식을 단다")
    func storeWaitsForDurableDraft() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        drafts.holdNextSave()
        await draw(store)

        // 초안을 쓰는 중이다 — 저장소 저장은 시작하지도 않았다.
        #expect(store.state.isSavingDrafts)
        #expect(store.state.saveStatus == .idle)
        #expect(spy.appliedGenerations.value.isEmpty)

        drafts.release()
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        #expect(spy.applied.value.count == 1)
        // 저장소로 갈 초안은 "보내는 중" 으로 먼저 남고, 저장을 마친 뒤 "들어감" 이 된다.
        #expect(drafts.saves.value.map(\.storeState) == [.sending])
        while drafts.stored(in: accountA).first?.storeState != .stored { await Task.yield() }
        await end(store, environment)
    }

    @Test("초안을 남기지 못하면 저장소 저장이 대신하지 않는다 — 다시 시도해 초안이 남은 뒤에 보낸다")
    func draftFailureStopsStoreWriteUntilRetry() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        drafts.failures.setValue(1)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        await draw(store)
        await store.receive(\.draftsSaved)

        #expect(store.state.draftFailureCount == 1)
        #expect(store.state.saveStatus == .idle)
        #expect(spy.appliedGenerations.value.isEmpty)
        #expect(drafts.stored(in: accountA).isEmpty)

        // 「다시 시도」 · 비활성화가 같은 경로로 다시 남긴다.
        await store.send(.flushPending)
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        #expect(store.state.draftFailureCount == nil)
        #expect(spy.applied.value.count == 1)
        #expect(drafts.stored(in: accountA).count == 1)
        await end(store, environment)
    }

    /// 저장소 저장은 끝났는데 표식을 남기기 전에 앱이 끝났다 — 초안은 "보내는 중" 으로 남는다.
    @Test("표식을 남기기 전에 끝난 초안은 행이 그대로면 겹치지 않고, 그 절을 지운 뒤에도 되살아나지 않는다")
    func draftWithoutMarkerIsNeitherLostNorResurrected() async throws {
        let spy = spyWithVerseOne()
        let drafts = RecordingDraftStore()
        drafts.markFailures.setValue(1)
        let firstEnvironment = ControlledEditEnvironment(confirmed(accountA, 1))
        let first = makeStore(spy: spy, results: [replaceVerseOne("r1")], environment: firstEnvironment, drafts: drafts)
        await composeAndSubscribe(first, firstEnvironment)
        await draw(first)
        await first.receive(\.saveFinished)
        await end(first, firstEnvironment)

        let kept = try #require(drafts.stored(in: accountA).first)
        #expect(kept.storeState == .sending)

        // 다시 실행: 저장소에는 그 편집이 들어가 있다 — 겹치지 않고 초안만 남긴다.
        spy.snapshots = { _ in [verseOneRow(lineData: Data("r1".utf8))] }
        let secondEnvironment = ControlledEditEnvironment(confirmed(accountA, 2))
        let second = makeStore(spy: spy, results: [], environment: secondEnvironment, drafts: drafts)
        await composeAndSubscribe(second, secondEnvironment)

        #expect(second.state.drafts.adopted[place] == nil)
        #expect(second.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("r1".utf8))
        #expect(drafts.stored(in: accountA).count == 1)
        await end(second, secondEnvironment)

        // 또 다시 실행: 그 사이 그 절을 지웠다(활성 행은 비고 보관 행이 내용을 든다). 되살리지 않는다.
        spy.snapshots = { _ in [
            verseOneRow(lineData: nil),
            VerseDrawingSnapshot(verse: 1, rowID: BibleDrawingRowID(raw: "archive"), isPresent: false,
                                 updateDate: Date(timeIntervalSince1970: 1_500), lineData: Data("r1".utf8), drawingVersion: 3,
                                 metadata: CanvasTestSupport.metadata())
        ] }
        let thirdEnvironment = ControlledEditEnvironment(confirmed(accountA, 3))
        let third = makeStore(spy: spy, results: [], environment: thirdEnvironment, drafts: drafts)
        await composeAndSubscribe(third, thirdEnvironment)

        #expect(third.state.drafts.adopted[place] == nil)
        #expect(third.state.loadedDrawings?.first { $0.rowID == CanvasTestSupport.rowA }?.lineData == nil)
        #expect(drafts.stored(in: accountA).count == 1)
        await end(third, thirdEnvironment)
    }

    /// ACC-1 F29 를 **기존 필기 수정**으로 본다 — 전송된 적 있는 행이면 서버의 옛 내용으로 돌아온다.
    @Test("고친 필기의 행이 옛 내용으로 돌아오면 그 초안이 유일한 사본이다 — 이어 보이고 이어 쓴다")
    func existingVerseF29ContinuesWhenRowReturnsToBase() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [replaceVerseOne("r1")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.saveFinished)
        while drafts.stored(in: accountA).first?.storeState != .stored { await Task.yield() }

        // A → B: 미러링이 A 의 행을 지운다.
        spy.snapshots = { _ in [] }
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.loadedDrawings?.isEmpty == true)

        // B → A: 서버에 있던 **고치기 전** 내용만 돌아왔다.
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        environment.change(to: confirmed(accountA, 3))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("r1".utf8))
        #expect(store.state.drafts.adopted[place] == drafts.stored(in: accountA).first?.ref)
        #expect(store.state.drafts.inherited[place] == nil)
        #expect(store.state.writesStore(verse: 1))
        await end(store, environment)
    }

    @Test("고친 필기의 행이 사라지고 그 절이 비었으면 기준이 없어도 보이고, 보이기만 한다")
    func existingVerseF29ShowsOnlyWhenRowIsGone() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [replaceVerseOne("r1")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.saveFinished)
        while drafts.stored(in: accountA).first?.storeState != .stored { await Task.yield() }

        // 그 행은 올라간 적이 없다 — A 로 돌아와도 그 절이 비어 있다.
        spy.snapshots = { _ in [] }
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)
        environment.change(to: confirmed(accountA, 3))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        let kept = try #require(drafts.stored(in: accountA).first)
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("r1".utf8))
        #expect(store.state.drafts.adopted[place] == kept.ref)
        #expect(store.state.drafts.inherited[place] == kept.provenance)
        #expect(!store.state.writesStore(verse: 1))
        await end(store, environment)
    }

}

/// 1절 행의 저장소 스냅숏 — 내용만 바꿔 준다. 저장소 대역의 클로저(격리 밖)에서 쓰므로 자유 함수로 둔다.
private func verseOneRow(lineData: Data?) -> VerseDrawingSnapshot {
    VerseDrawingSnapshot(
        verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true, updateDate: Date(timeIntervalSince1970: 2_000),
        lineData: lineData, drawingVersion: lineData == nil ? nil : 3, metadata: lineData == nil ? nil : CanvasTestSupport.metadata()
    )
}
