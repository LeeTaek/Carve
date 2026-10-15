//
//  CarveDetailBackgroundLayoutTesting.swift
//  CarveFeatureTest
//
//  홈으로 나간 사이(백그라운드) 시스템이 다시 배치한 화면의 실측을 믿지 않는다 — `CarveDetailFeature+Background.swift`.
//  iPadOS 18 은 앱 전환기 스냅샷을 compact 폭으로 찍으며 필사 컬럼을 다시 짓고, 그때 행 frame 이 컬럼 중심만큼 어긋난 채 들어와
//  돌아온 뒤 획이 372pt 왼쪽에 다시 그려지고 새 획이 막혔다(2026-10-15 18.6 시뮬레이터 재현).
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 본문 읽기를 부른 장만 남기고 실패한다 — 읽기 뒤 `setSentence` · 캔버스 조회(공유 저장소)로 이어지지 않게 한다.
private struct RecordingBibleTextClient: BibleTextClient {
    let requested: LockIsolated<[BibleChapter]>

    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        requested.withValue { $0.append(chapter) }
        throw BibleTextClientError.fetchSentenceError
    }
}

@Suite("백그라운드 배치 — 필사 컬럼 실측 미루기와 복귀 재측정")
@MainActor
struct CarveDetailBackgroundLayoutTesting {
    /// 행의 장은 화면이 보고 있는 장(`headerState.currentTitle`)과 같게 둔다 — 같은 장 다시 읽기 판정이 이 둘을 견준다.
    private let chapter = CarveDetailFeature.State.initialState.headerState.currentTitle

    private func sentences(count: Int, chapter: BibleChapter? = nil) -> [BibleVerse] {
        (1...count).map { BibleVerse(title: chapter ?? self.chapter, verse: $0, sentence: "본문 \($0)") }
    }

    private func rowID(_ verse: Int) -> SentencesWithDrawingFeature.State.ID {
        SentencesWithDrawingFeature.State.rowID(chapter: chapter, verse: verse)
    }

    /// `reduce(into:)` 를 직접 호출한다 — 상태 전이만 보고 효과는 버린다.
    private func reduce(_ state: inout CarveDetailFeature.State, _ action: CarveDetailFeature.Action) {
        _ = CarveDetailFeature().reduce(into: &state, action: action)
    }

    /// 세로 iPad mini 배치 — 원문 반쪽 | 필기 반쪽(x 372)이고 행은 컬럼 폭 전체다. 한 줄 절(높이 30)을 절 사이 30 으로 쌓아
    /// 빌더의 예측 위치와 같게 둔다(Δ 0). `xShift` · `yShift` 만큼 행 frame 을 옮긴다.
    private func rowGeometry(xShift: CGFloat = 0, yShift: CGFloat = 0) -> [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] {
        Dictionary(uniqueKeysWithValues: (1...3).map { verse in
            // 행 상단 = 열 라벨 줄(64) + 절마다 (본문 30 + 절 사이 30). 행 안 캔버스 영역은 위 padding 2 아래에 있다.
            let top = ChapterLayoutHosting.columnHeaderHeight + CGFloat(verse - 1) * 60
            return (rowID(verse), VerseRowGeometry(
                underlineOffsets: [30],
                rowFrame: CGRect(x: xShift, y: top + yShift, width: 744, height: 34),
                canvasFrameInRow: CGRect(x: 372, y: 2, width: 372, height: 30)
            ))
        })
    }

    /// 장을 읽고 전 절을 실측해 레이아웃 · 열 원점이 정해진 상태.
    private func measuredState() -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 3)))
        reduce(&state, .view(.verseGeometryMeasured(rowGeometry())))
        return state
    }

    @Test("백그라운드 동안 온 행 실측 · 폭은 반영하지 않는다 — 측정 · 레이아웃 · 열 원점이 나가기 전 그대로다")
    func backgroundMeasurementIsDeferred() {
        // Given: 열 원점 (372, 0) 으로 레이아웃이 완성된 화면
        var state = measuredState()
        let before = state.chapterLayout
        #expect(before.columnOrigin == CGPoint(x: 372, y: 0))
        #expect(before.isReady)
        #expect(before.worstFrameDelta?.magnitude == 0)

        // When: 홈으로 나간 사이 스냅샷 배치가 폭 207 과 컬럼 중심만큼 어긋난 행 frame 을 보고한다
        reduce(&state, .view(.sceneEnteredBackground))
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 207)))
        reduce(&state, .view(.verseGeometryMeasured(rowGeometry(xShift: -372, yShift: -3768.5))))

        // Then: 측정은 그대로라 열 원점 · Δ 판정이 바뀌지 않고, 다시 잴 일만 남긴다
        #expect(state.chapterLayout == before)
        #expect(state.chapterLayout.columnOrigin == CGPoint(x: 372, y: 0))
        #expect(state.chapterLayout.layoutDeltaVerdict?.blocksInput != true)
        #expect(state.hasBackgroundMeasurement)
        #expect(state.deferredWritingWidth == 207)
        #expect(state.columnMeasureGeneration == 0)
    }

    @Test("다시 활성이 되면 컬럼을 새로 재는 세대를 올리고, 돌아온 폭이 같으면 레이아웃을 다시 짓지 않는다")
    func returningRemeasuresColumnOnce() {
        // Given: 백그라운드에서 폭 207 → 372 로 되돌아오는 배치를 겪었다
        var state = measuredState()
        let buildCount = state.chapterLayout.buildCount
        reduce(&state, .view(.sceneEnteredBackground))
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 207)))
        reduce(&state, .view(.verseGeometryMeasured(rowGeometry(xShift: -372, yShift: -3768.5))))
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))

        // When: 앱이 다시 활성이 된다
        reduce(&state, .view(.sceneBecameActive))

        // Then: 컬럼을 한 번 새로 재고, 미룬 폭은 지금 폭과 같아 레이아웃이 다시 지어지지 않는다
        #expect(!state.isInBackground)
        #expect(!state.hasBackgroundMeasurement)
        #expect(state.deferredWritingWidth == nil)
        #expect(state.columnMeasureGeneration == 1)
        #expect(state.chapterLayout.writingWidth == 372)
        #expect(state.chapterLayout.buildCount == buildCount)

        // When: 새로 지은 컬럼이 지금 배치를 다시 보고한다
        reduce(&state, .view(.verseGeometryMeasured(rowGeometry())))

        // Then: 평소처럼 반영된다
        #expect(state.chapterLayout.columnOrigin == CGPoint(x: 372, y: 0))
        #expect(state.chapterLayout.layoutDeltaVerdict?.blocksInput != true)
    }

    @Test("백그라운드 동안 아무 실측도 오지 않았으면 돌아와도 컬럼을 다시 재지 않는다 (26.x)")
    func quietBackgroundKeepsColumn() {
        var state = measuredState()

        reduce(&state, .view(.sceneEnteredBackground))
        reduce(&state, .view(.sceneBecameActive))

        #expect(!state.isInBackground)
        #expect(state.columnMeasureGeneration == 0)
    }

    @Test("백그라운드 동안 실제로 바뀐 폭은 돌아와서 마지막 값으로 적용한다")
    func changedWidthIsAppliedOnReturn() throws {
        // Given: 백그라운드 동안 폭이 207 을 거쳐 500 으로 바뀌었다
        var state = measuredState()
        let buildCount = state.chapterLayout.buildCount
        reduce(&state, .view(.sceneEnteredBackground))
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 207)))
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 500)))
        #expect(state.chapterLayout.writingWidth == 372)

        // When
        reduce(&state, .view(.sceneBecameActive))

        // Then: 평소 폭 변경처럼 마지막 폭으로 레이아웃을 다시 짓는다
        #expect(state.chapterLayout.writingWidth == 500)
        let layout = try #require(state.chapterLayout.layout)
        #expect(layout.writingWidth == 500)
        #expect(state.chapterLayout.buildCount == buildCount + 1)
        #expect(state.columnMeasureGeneration == 1)
    }

    @Test("활성일 때의 실측은 그대로 반영한다")
    func foregroundMeasurementStillApplies() {
        var state = measuredState()

        reduce(&state, .view(.verseGeometryMeasured(rowGeometry(xShift: 10))))

        #expect(state.chapterLayout.columnOrigin == CGPoint(x: 382, y: 0))
        #expect(!state.hasBackgroundMeasurement)
    }

    @Test("백그라운드 배치에서 화면이 다시 나타나면 보고 있던 장을 읽지 않고, 장 이동 · 딥링크가 보내는 읽기는 그대로 한다")
    func appearanceInBackgroundSkipsOnlyRedundantRead() async {
        // Given: 장을 보고 있다가 홈으로 나갔다
        var initial = measuredState()
        reduce(&initial, .view(.sceneEnteredBackground))
        let requested = LockIsolated<[BibleChapter]>([])
        let store = Store(initialState: initial) {
            CarveDetailFeature()
        } withDependencies: {
            $0.bibleTextClient = RecordingBibleTextClient(requested: requested)
        }

        // When: 스냅샷 배치에서 필사 화면이 다시 나타난다 → Then: 읽지 않는다
        await store.send(.view(.appeared)).finish()
        #expect(requested.value.isEmpty)

        // When: 같은 장이라도 장 이동 · 딥링크(위젯 → 절)가 직접 읽기를 보낸다 → Then: 읽는다(스크롤 목표가 새 본문에서 처리된다)
        await store.send(.view(.fetchSentence)).finish()
        #expect(requested.value == [chapter])
    }

    @Test("활성일 때 화면이 나타나면 본문을 읽는다")
    func appearanceInForegroundReadsChapter() async {
        let requested = LockIsolated<[BibleChapter]>([])
        let store = Store(initialState: measuredState()) {
            CarveDetailFeature()
        } withDependencies: {
            $0.bibleTextClient = RecordingBibleTextClient(requested: requested)
        }

        await store.send(.view(.appeared)).finish()

        #expect(requested.value == [chapter])
    }

    @Test("백그라운드에서 보고 있던 장을 다시 읽으라는 요청만 건너뛴다")
    func onlyRedundantBackgroundFetchIsSkipped() {
        var state = measuredState()
        #expect(!CarveDetailFeature.isRedundantBackgroundFetch(state))

        // 백그라운드 배치에서 화면이 다시 나타나 같은 장을 읽으려 한다 → 건너뛴다
        reduce(&state, .view(.sceneEnteredBackground))
        #expect(CarveDetailFeature.isRedundantBackgroundFetch(state))

        // 행이 다른 장이면(장 이동 · 번역본 전환 뒤) 읽는다
        var moved = state
        reduce(&moved, .setSentence(sentences(count: 2, chapter: BibleChapter(title: .exodus, chapter: 2))))
        #expect(!CarveDetailFeature.isRedundantBackgroundFetch(moved))

        // 아직 읽은 장이 없으면(백그라운드 실행) 읽는다
        var empty = CarveDetailFeature.State.initialState
        reduce(&empty, .view(.sceneEnteredBackground))
        #expect(!CarveDetailFeature.isRedundantBackgroundFetch(empty))
    }
}
