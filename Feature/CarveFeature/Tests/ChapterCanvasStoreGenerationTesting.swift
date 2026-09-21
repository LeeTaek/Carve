//
//  ChapterCanvasStoreGenerationTesting.swift
//  CarveFeatureTest
//
//  전체 삭제 뒤에 실행되는 저장 (리뷰 P1-1, `DrawingStoreGeneration`).
//
//  설정의 삭제는 DB 를 지운 **뒤에** 이 화면에 알린다. 알림이 오기 전에도 화면은 세 경로로 삭제와 부딪친다.
//  1. 이미 요청된 저장이 삭제 뒤에 실행된다 → 저장소가 세대로 거절한다
//  2. 실패로 남은 미저장분을 다시 시도한다 → 원래 기준 세대로 가서 거절된다
//  3. 조회 결과가 기준과 다른 세대다 → 그 결과로 합성하지 않는다
//  어느 경로든 지운 데이터 기준의 편집은 저장되지 않고, 화면은 삭제 뒤처리를 한다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

private extension RepositorySpy {
    /// 설정에서 전부 지운 것처럼 — DB 가 비고 세대가 오른다. **화면에는 알리지 않는다.**
    func eraseWithoutNotice() {
        snapshots = { _ in [] }
        generation.withValue { $0 = DrawingStoreGeneration(raw: $0.raw + 1) }
    }
}

@Suite("전체 삭제 뒤에 실행되는 저장 — 저장소 세대")
@MainActor
struct ChapterCanvasStoreGenerationTesting {
    private let before = DrawingStoreGeneration(raw: 0)
    private let after = DrawingStoreGeneration(raw: 1)
    private let chapterB = BibleChapter(title: .jonah, chapter: 3)

    /// 효과가 모두 끝난 뒤 받은 액션까지 반영한다 — 도착 순서를 테스트가 정하지 않는 흐름용.
    /// `TestStore.state` 는 받은 액션을 소비해야 갱신되므로 `finish()` 만으로는 옛 상태가 보인다.
    private func settle(_ store: TestStoreOf<ChapterCanvasFeature>) async {
        await store.finish()
        await store.skipReceivedActions(strict: false)
    }

    @Test("삭제 전에 요청된 저장이 삭제 뒤에 실행돼 거절되면 실패로 알리지 않고, 미저장분을 버린 뒤 새 세대로 다시 읽는다")
    func staleRejectionClearsWithoutFailureNotice() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("a")]))
        await CanvasTestSupport.compose(store)
        #expect(store.state.storeGeneration == before)

        // 저장은 요청됐지만 아직 실행되지 않았다.
        spy.holdNextApply()
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        guard case .saving = store.state.saveStatus else {
            Issue.record("저장이 시작되지 않았다: \(store.state.saveStatus)")
            return
        }

        // 그 사이 설정에서 전부 지웠다. 저장은 삭제 뒤에 실행된다.
        spy.eraseWithoutNotice()
        spy.releaseApply()
        await store.receive(\.saveFinished)

        // 저장소는 조회할 때의 세대를 받았고, 아무것도 쓰지 않았다.
        #expect(spy.appliedGenerations.value == [before])
        #expect(spy.applied.value.isEmpty)
        // ★ 실패 안내 · 재시도 대상으로 남기지 않는다 — 다시 보내도 매번 같은 이유로 거절된다.
        #expect(store.state.saveRetryCount == nil)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.saveStatus == .idle)
        #expect(store.state.localSaveIndicator == .none)

        await store.receive(\.drawingsLoaded)
        #expect(store.state.storeGeneration == after)
        #expect(store.state.loadedDrawings == [])

        // 뒤따라 온 삭제 알림은 같은 정리를 한 번 더 할 뿐이다.
        await store.send(.drawingDataCleared)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.storeGeneration == after)
        #expect(spy.applied.value.isEmpty)
    }

    @Test("실패로 남은 이전 장 미저장분은 장을 바꿔도 원래 기준 세대로 다시 시도한다 — 새 장 조회의 세대로 통과하지 않는다")
    func retryAfterSwitchKeepsOriginalGeneration() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("디스크 오류")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("a")]))
        await CanvasTestSupport.compose(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 1)
        let attemptsBeforeErase = spy.applied.value.count

        // 설정에서 전부 지웠고 화면은 아직 모른다. 장 전환은 flush 지점이라 실패한 batch 를 다시 보내고, 새 장을 조회한다.
        // 재시도의 거절과 새 장 조회 중 무엇이 먼저 도착해도 결과가 같아야 한다. 거절 정리(`finishSave`)와 조회 세대 대조
        // (`finishLoad`) 중 하나만 있어도 통과하고, 둘 다 없으면 미저장분이 새 세대의 기준으로 남아 실패한다.
        spy.eraseWithoutNotice()
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        await settle(store)

        // ★ 재시도는 삭제 전 세대로 갔다. 새 장 조회의 세대로 보냈다면 지운 장의 필사가 저장됐다.
        #expect(spy.appliedGenerations.value == [before, before])
        #expect(spy.applied.value.count == attemptsBeforeErase)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.saveRetryCount == nil)
        #expect(store.state.chapter == chapterB)
        #expect(store.state.storeGeneration == after)
    }

    @Test("기준과 다른 세대의 조회 결과로는 합성하지 않는다 — 물러난 장의 늦은 편집이 새 세대로 저장되지 않는다")
    func mismatchedLoadDropsWorkBasedOnErasedData() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("late")]))
        await CanvasTestSupport.compose(store)
        let erasedCanvasGeneration = store.state.renderedRevision

        // 설정에서 전부 지웠고 화면은 아직 모른다. 그 사이 장을 넘긴다 — 이전 장의 편집 문맥은 물러나 남는다.
        spy.eraseWithoutNotice()
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        await settle(store)

        // 세대가 달라 그 결과로 합성하지 않고, 지운 데이터 기준의 문맥을 버린 뒤 다시 조회했다.
        #expect(spy.loadedChapters.value == [CanvasTestSupport.chapter, chapterB, chapterB])
        #expect(store.state.retiredSession == nil)
        #expect(store.state.storeGeneration == after)

        // 지워지기 전 캔버스의 늦은 보고가 이제 도착한다.
        await store.send(.editEnded(CanvasTestSupport.edit("late", generation: erasedCanvasGeneration)))
        await settle(store)

        // ★ 계산할 기준이 사라졌으므로 버린다. 문맥이 남아 있었다면 지운 잉크가 새 세대로 저장됐다.
        #expect(spy.appliedGenerations.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
    }
}

// MARK: - 조회 실패 — 기준 없이 입력을 열지 않는다

@Suite("조회 실패 — 기준(내용과 세대) 없이 입력을 열지 않는다")
@MainActor
struct ChapterCanvasLoadFailureTesting {
    private let after = DrawingStoreGeneration(raw: 1)

    private func settle(_ store: TestStoreOf<ChapterCanvasFeature>) async {
        await store.finish()
        await store.skipReceivedActions(strict: false)
    }

    /// ★ 리뷰가 짚은 순서. 이전 구현은 전부 지운 뒤 내용을 `[]` 로 두어, 다시 읽기가 실패하면 빈 내용으로 합성해 입력을 열었다.
    /// 그 뒤의 필기는 세대가 없어 저장을 시작하지 못하고, 실패 안내도 없이 큐에 쌓였으며 `flushPending` 으로도 풀리지 않았다.
    @Test("전부 지운 뒤 다시 읽기가 실패하면 입력을 닫아 두고, 다시 읽기에 성공한 뒤의 새 필기는 새 세대로 저장된다")
    func reloadFailureAfterEraseKeepsInputClosedUntilRetry() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("after")]))
        await CanvasTestSupport.compose(store)

        // 설정에서 전부 지웠고, 이어진 다시 읽기가 실패한다.
        spy.eraseWithoutNotice()
        spy.loadFailures.setValue(["디스크 오류"])
        await store.send(.drawingDataCleared)
        await store.receive(\.drawingsLoaded)

        #expect(!store.state.isInputEnabled)
        #expect(store.state.renderedData == nil, "지운 잉크가 화면에 남지 않는다")
        #expect(store.state.storeGeneration == nil)
        #expect(store.state.blockingLoadFailure != nil, "화면이 안내와 「다시 시도」 를 띄운다")
        #expect(store.state.localSaveIndicator == .none)

        // 닫히기 전 캔버스의 늦은 보고가 와도 계산할 기준이 없어 버린다 — 저장될 곳 없는 미저장분을 만들지 않는다.
        await store.send(.editEnded(CanvasTestSupport.edit("stray", generation: store.state.renderedRevision)))
        await settle(store)
        await store.send(.flushPending)
        await settle(store)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(spy.appliedGenerations.value.isEmpty)

        // 다시 읽기에 성공하면 새 세대로 합성하고 입력을 연다.
        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)
        #expect(store.state.storeGeneration == after)
        #expect(store.state.blockingLoadFailure == nil)

        // 그 뒤의 새 필기는 새 세대로 저장된다.
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("after", generation: store.state.renderedRevision)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(spy.appliedGenerations.value == [after])
        #expect(spy.applied.value.count == 1)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.localSaveIndicator == .saved)
    }

    @Test("첫 조회가 실패한 장은 입력을 닫아 두고 안내하며, 다시 읽기에 성공하면 연다 — 이전에는 다시 읽을 길이 없었다")
    func firstLoadFailureOffersRetry() async {
        let spy = RepositorySpy()
        spy.loadFailures.setValue(["디스크 오류"])
        let store = CanvasTestSupport.makeStore(spy: spy)
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(!store.state.isInputEnabled)
        #expect(store.state.blockingLoadFailure != nil)

        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.isInputEnabled)
        #expect(store.state.blockingLoadFailure == nil)
        #expect(spy.loadedChapters.value == [CanvasTestSupport.chapter, CanvasTestSupport.chapter])
    }

    @Test("합성된 장에서는 다시 읽기 요청을 무시한다 — 재조회 실패는 마지막으로 알던 내용으로 이미 복구했다")
    func retryIsIgnoredWhenComposed() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)

        await store.send(.retryLoad)

        #expect(spy.loadedChapters.value == [CanvasTestSupport.chapter])
    }
}
