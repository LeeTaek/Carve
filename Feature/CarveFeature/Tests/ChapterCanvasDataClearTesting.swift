//
//  ChapterCanvasDataClearTesting.swift
//  CarveFeatureTest
//
//  설정의 「모든 필사 데이터 삭제」 뒤처리.
//
//  고정하는 성질
//  1. 미저장분 · 큐 · 활성 행을 **버린다** — 남기면 다음 저장이 방금 지운 잉크를 되살린다
//  2. 레이아웃은 그대로 두고 DB 에서 다시 합성한다 (본문은 지워지지 않았다)
//  3. 필사 화면은 공유 세대를 **값으로** 비교한다 — 지워지는 순간 트리에 없어도 놓치지 않는다
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("전체 삭제 — ChapterCanvasFeature 뒤처리")
@MainActor
struct ChapterCanvasDataClearTesting {

    @Test("미저장분과 활성 행을 버리고 DB 에서 다시 합성한다 — 지운 잉크가 다시 저장되지 않는다")
    func clearDiscardsPendingWorkAndReloads() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        // 저장이 실패해 미저장분이 큐에 남은 상태를 만든다 (§8-3 5번 — 실패하면 항목을 유지한다).
        spy.applyFailures.setValue([.persistenceFailed("boom")])
        let results = LockIsolated([CanvasTestSupport.createResult("a")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)

        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(!store.state.pendingMutations.isEmpty)
        #expect(store.state.activeRowIDs[1] == CanvasTestSupport.rowA)
        let appliedBeforeClear = spy.applied.value.count
        let layoutBeforeClear = store.state.layout

        // 설정에서 전부 지웠다 — DB 도 비었다.
        spy.snapshots = { _ in [] }
        await store.send(.drawingDataCleared)

        // 1. 버린다. 이 명령들이 가리키는 행은 DB 에 없다.
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.editQueue.isEmpty)
        #expect(store.state.activeRowIDs.isEmpty)
        #expect(store.state.baselineData == nil)
        #expect(store.state.saveStatus == .idle)
        // 2. 레이아웃은 그대로다 — 본문은 지워지지 않았으므로 다시 잴 것이 없다.
        #expect(store.state.layout == layoutBeforeClear)

        await store.receive(\.drawingsLoaded)
        // 재조회는 했고, 버린 미저장분을 다시 저장하지는 않았다.
        #expect(spy.loadedChapters.value.count == 2)
        #expect(spy.applied.value.count == appliedBeforeClear)
    }

    @Test("지우는 중이던 절 보관 작업과 절 메뉴도 접는다 — 대상 행이 사라졌다")
    func clearFoldsEraseTaskAndMenu() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)

        await store.send(.eraseRequested(at: CGPoint(x: 10, y: 15)))
        #expect(store.state.eraseAlert != nil)

        spy.snapshots = { _ in [] }
        await store.send(.drawingDataCleared)

        #expect(store.state.eraseAlert == nil)
        #expect(store.state.eraseTask == nil)
        #expect(store.state.verseMenu == nil)
        await store.receive(\.drawingsLoaded)
    }
}

// MARK: - 필사 화면 배선

@Suite("전체 삭제 — 필사 화면이 공유 세대를 값으로 비교한다")
@MainActor
struct CarveDetailDataClearTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)

    private func makeStore(spy: FavoriteRepositorySpy) -> StoreOf<CarveDetailFeature> {
        var state = CarveDetailFeature.State.initialState
        state.favoriteChapter = Self.chapter
        return Store(initialState: state) {
            CarveDetailFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = spy
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
            $0.drawingRepository = RepositorySpy()
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.uuid = .incrementing
            $0.undoManager = SharedUndoManager()
        }
    }

    /// 다른 필사 화면 테스트와 같은 관용구 — 효과가 끝나기를 조건으로 기다린다.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("세대가 오르면 즐겨찾기를 다시 읽고, 같은 세대로는 다시 읽지 않는다")
    func revisionChangeReloadsOnlyOnce() async throws {
        let spy = FavoriteRepositorySpy()
        let store = makeStore(spy: spy)

        // 아직 오르지 않았다 — 뷰가 처음 붙을 때(`initial: true`)도 아무 일이 없어야 한다.
        await store.send(.view(.drawingDataRevisionChanged)).finish()
        #expect(spy.loadedChapters.value.isEmpty)

        // 설정이 전부 지우고 세대를 올렸다.
        store.state.$drawingDataRevision.withLock { $0 = 7 }
        await store.send(.view(.drawingDataRevisionChanged)).finish()
        try await waitUntil { spy.loadedChapters.value.count == 1 }
        #expect(store.state.seenDrawingDataRevision == 7)

        // 같은 세대로 다시 와도(뷰가 트리로 돌아왔을 때) 두 번 읽지 않는다.
        await store.send(.view(.drawingDataRevisionChanged)).finish()
        #expect(spy.loadedChapters.value.count == 1)
    }
}
