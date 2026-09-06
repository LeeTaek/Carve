//
//  ChapterCanvasHistoryTesting.swift
//  CarveFeatureTest
//
//  Phase 3 (3/3) — B 구조의 히스토리 요청(롱프레스 → 절 판정 → delegate)과 디버그 dirtyBounds 기록.
//  스텁·지원 타입은 ChapterCanvasFeatureTesting.swift 의 것을 쓴다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

// MARK: - (3/3) 히스토리 메뉴 · 디버그 dirtyBounds

@Suite("Phase 3 — ChapterCanvasFeature · 히스토리 요청 (3/3)")
@MainActor
struct ChapterCanvasHistoryTesting {
    @Test("캔버스를 길게 누른 자리의 절로 히스토리를 요청한다 — 컬럼 왼쪽(텍스트 쪽)은 같은 행으로, 세로로 벗어나면 무시, 합성 전엔 무시")
    func longPressResolvesVerseFromRenderedLayout() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)

        // 합성 전 — 레이아웃이 없으므로 아무 일도 없다.
        await store.send(.historyRequested(at: CGPoint(x: 10, y: 45)))

        await CanvasTestSupport.compose(store)
        // columnOrigin 이 바뀌면 재합성 뒤의 renderedColumnOrigin 을 기준으로 판정한다.
        let origin = CGPoint(x: 100, y: 0)
        await store.send(.columnOriginChanged(origin)) {
            $0.columnOrigin = origin
            $0.isReloading = true
        }
        await store.receive(\.drawingsLoaded) {
            $0.renderedColumnOrigin = origin
            $0.isReloading = false
        }

        // layout y 45 → verse 2 (v1 [0,30) · v2 [30,60) · v3 [60,90]).
        await store.send(.historyRequested(at: CGPoint(x: 110, y: 45)))
        await store.receive(.delegate(.showHistory(verse: 2)))
        // 텍스트 컬럼 위(content x 50 → layout x −50)는 x 만 안으로 당겨 같은 행이다.
        await store.send(.historyRequested(at: CGPoint(x: 50, y: 45)))
        await store.receive(.delegate(.showHistory(verse: 2)))
        // 캔버스 아래 바깥은 무시한다.
        await store.send(.historyRequested(at: CGPoint(x: 110, y: 5_000)))
        #expect(store.state.isInputEnabled)
    }

    @Test("editEnded 의 dirtyBounds 와 그 상단이 속한 절을 디버그 오버레이용으로 남긴다")
    func dirtyBoundsAreRecordedForOverlay() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)

        let bounds = CGRect(x: 5, y: 35, width: 40, height: 10)
        await store.send(.editEnded(CanvasTestSupport.edit("1", dirtyBounds: bounds))) {
            $0.lastDirtyBounds = bounds
            $0.lastEditedVerse = 2
        }
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)

        let next = BibleChapter(title: .jonah, chapter: 3)
        await store.send(.load(chapter: next, expectedVerseCount: 3)) {
            $0.lastDirtyBounds = nil
            $0.lastEditedVerse = nil
        }
        await store.receive(\.drawingsLoaded)
    }
}
