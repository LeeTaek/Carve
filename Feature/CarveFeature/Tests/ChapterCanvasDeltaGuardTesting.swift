//
//  ChapterCanvasDeltaGuardTesting.swift
//  CarveFeatureTest
//
//  레이아웃 Δ 안전망 (설계 §14 — D9 R13).
//  예측 좌표와 실제 렌더가 한 줄 이상 어긋나면 **새 획 입력만** 막고 합성·표시·저장은 그대로 둔다.
//  스텁(`CanvasTestSupport` · `RepositorySpy`)은 `ChapterCanvasFeatureTesting.swift` 의 것을 그대로 쓴다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture
import Dependencies

@testable import CarveFeature

// MARK: - 판정이 상태에 미치는 영향

@Suite("Phase 3 — ChapterCanvasFeature · 레이아웃 Δ 안전망")
@MainActor
struct ChapterCanvasDeltaGuardTesting {
    /// 임계값 초과 판정 (한 줄 30pt 를 넘는 87.5pt — D9 시편 119편의 실측 모양).
    private static func blocking(verse: Int = 176) -> LayoutDeltaVerdict {
        LayoutDeltaVerdict(verse: verse, magnitude: 87.5, topDelta: 87.5, heightDelta: 0, lineSpace: 30, blocksInput: true)
    }

    /// 허용치 안의 판정.
    private static func open(magnitude: CGFloat = 0.5) -> LayoutDeltaVerdict {
        LayoutDeltaVerdict(verse: 2, magnitude: magnitude, topDelta: magnitude, heightDelta: 0, lineSpace: 30, blocksInput: false)
    }

    @Test("Δ 가 허용치 안이면 입력이 열린 채로 있다")
    func inputStaysOpenBelowThreshold() async {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)
        #expect(store.state.isDrawingInputEnabled)

        await store.send(.layoutDeltaEvaluated(Self.open())) { $0.layoutDelta = Self.open() }

        #expect(store.state.isDrawingInputEnabled)
        #expect(store.state.isInputEnabled)
    }

    @Test("Δ 가 한 줄을 넘으면 새 입력만 닫히고 합성·표시·저장·flush 는 계속 동작한다 (§14 안전망의 핵심)")
    func blockingVerdictClosesOnlyDrawingInput() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("a")]))
        await CanvasTestSupport.compose(store)
        let composedData = store.state.renderedData

        await store.send(.layoutDeltaEvaluated(Self.blocking())) { $0.layoutDelta = Self.blocking() }

        // ① 새 획 입력만 닫힌다.
        #expect(!store.state.isDrawingInputEnabled)
        // ② 합성 게이트(§6-2)는 그대로 열려 있다 — 잉크가 화면에서 사라지지 않는다.
        #expect(store.state.isInputEnabled)
        #expect(store.state.isComposed)
        #expect(store.state.renderedData == composedData)
        #expect(store.state.renderedLayout == CanvasTestSupport.layout)

        // ③ 차단 직전에 올라온 편집은 그대로 계산되고 저장된다 — 미저장분이 유실되지 않는다.
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(spy.applied.value.count == 1)
        #expect(store.state.isFullyPersisted)
        #expect(!store.state.isDrawingInputEnabled)   // 저장이 지나가도 차단은 유지

        // ④ flush 경로도 살아 있다.
        await store.send(.flushPending)
        #expect(store.state.isFullyPersisted)

        // ⑤ 판정이 풀리면 곧바로 다시 열린다.
        await store.send(.layoutDeltaEvaluated(Self.open())) { $0.layoutDelta = Self.open() }
        #expect(store.state.isDrawingInputEnabled)
    }

    @Test("차단 중에도 재합성(레이아웃 갱신)은 정상적으로 돈다")
    func recompositionStillRunsWhileBlocked() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)
        await store.send(.layoutDeltaEvaluated(Self.blocking())) { $0.layoutDelta = Self.blocking() }

        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        #expect(store.state.renderedLayout == CanvasTestSupport.otherLayout)
        #expect(store.state.isInputEnabled)
        #expect(!store.state.isDrawingInputEnabled)
    }

    @Test("장이 바뀌면 이전 장의 차단 판정을 물려받지 않는다 (§14 이월 상태)")
    func verdictDoesNotCarryOverToNextChapter() async {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)
        await store.send(.layoutDeltaEvaluated(Self.blocking())) { $0.layoutDelta = Self.blocking() }
        #expect(!store.state.isDrawingInputEnabled)

        let next = BibleChapter(title: .jonah, chapter: 3)
        await store.send(.load(chapter: next, expectedVerseCount: 3)) { $0.layoutDelta = nil }
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))

        #expect(store.state.layoutDelta == nil)
        #expect(store.state.isDrawingInputEnabled)
    }

    @Test("진입 뒤 실측 레이아웃이 한 번 더 와도 편집 중이면 pencil-up 뒤에 적용된다 (§8-1 · R13 예측 → 실측)")
    func measuredLayoutArrivingWhileEditingIsAppliedAfterPencilUp() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("a")]))
        // 예측 높이로 지어진 첫 레이아웃으로 합성된 상태.
        await CanvasTestSupport.compose(store)
        #expect(store.state.renderedLayout == CanvasTestSupport.layout)

        // 획 도중에 실측 높이로 다시 지어진 레이아웃이 도착한다.
        await store.send(.editBegan) { $0.isEditing = true }
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout)) {
            $0.pendingLayout = CanvasTestSupport.otherLayout
        }
        // 획 도중에는 적용되지 않는다 — 적용하면 그리던 획이 재합성으로 사라진다.
        #expect(store.state.layout == CanvasTestSupport.layout)
        #expect(store.state.renderedLayout == CanvasTestSupport.layout)

        // pencil-up — 편집이 먼저 이전 세대 기준으로 계산되고, 그 다음에 보류된 레이아웃이 적용된다.
        await store.send(.editEnded(CanvasTestSupport.edit("a"))) {
            $0.isEditing = false
            $0.pendingLayout = nil
            $0.layout = CanvasTestSupport.otherLayout
        }
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.renderedLayout == CanvasTestSupport.otherLayout)
        #expect(store.state.isInputEnabled)
        // 획은 자기 세대(예측 레이아웃) 기준으로 계산돼 저장됐다.
        #expect(spy.applied.value.count == 1)
    }
}

// MARK: - 안전망 배선 (뷰 경계 · 경로)

/// 판정이 **실제로 캔버스까지 닿는가**를 본다. 앞 suite 는 상태 계산만 보므로 배선이 끊겨도 통과한다.
///
/// | 끊길 수 있는 곳 | 여기서 고정하는 것 |
/// |---|---|
/// | `ChapterCanvasView.Display` 가 합성 게이트를 읽는다 | 표시 상태는 `isDrawingInputEnabled` 를 실어야 한다 |
/// | `forwardLayoutToSingleCanvas` 의 `usesSingleCanvas` 가드 | N-Canvas 에는 판정이 **effect 로도** 가지 않아야 한다 |
///
/// 경로 두 건은 리듀서를 직접 부르지 않고 **실제 `Store` 로 effect 를 태운다** — `reduce(into:)` 직접 호출은
/// effect 를 버리므로 가드를 지워도 상태가 그대로라 배선 회귀를 잡지 못한다.
@Suite("Phase 3 — Δ 안전망 배선 (뷰 경계 · N-Canvas/단일 Canvas 경로)")
@MainActor
struct ChapterCanvasDeltaGuardWiringTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    /// D9 시편 119편의 실측 모양 — 한 줄(30pt)을 넘는 87.5pt.
    private static func blocking() -> LayoutDeltaVerdict {
        LayoutDeltaVerdict(verse: 176, magnitude: 87.5, topDelta: 87.5, heightDelta: 0, lineSpace: 30, blocksInput: true)
    }

    // MARK: 뷰 경계

    @Test("캔버스에 넘기는 표시 상태는 합성 게이트가 아니라 새 획 게이트를 싣는다 (§14 안전망이 PencilKit 에 닿는 지점)")
    func displayCarriesDrawingInputGateNotComposeGate() async {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)
        #expect(ChapterCanvasView.Display(store.state).isInputEnabled)

        await store.send(.layoutDeltaEvaluated(Self.blocking())) { $0.layoutDelta = Self.blocking() }

        // 합성 게이트는 열려 있다 — 여기서 `isInputEnabled` 를 실으면 안전망이
        // `ChapterCanvasController` 의 `drawingGestureRecognizer.isEnabled` 까지 가지 못한다.
        #expect(store.state.isInputEnabled)
        #expect(!store.state.isDrawingInputEnabled)
        #expect(!ChapterCanvasView.Display(store.state).isInputEnabled)
    }

    // MARK: 경로 — 안전망은 단일 Canvas 에만 붙는다

    private func rowID(_ verse: Int) -> SentencesWithDrawingFeature.State.ID {
        "\(chapter.title.koreanTitle()).\(chapter.chapter).\(verse)"
    }

    private func sentences(count: Int) -> [BibleVerse] {
        (1...count).map { BibleVerse(title: chapter, verse: $0, sentence: "본문 \($0)") }
    }

    private func makeDetailStore(_ state: CarveDetailFeature.State) -> StoreOf<CarveDetailFeature> {
        Store(initialState: state) {
            CarveDetailFeature()
        } withDependencies: {
            $0.drawingRepository = RepositorySpy()
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.undoManager = SharedUndoManager()
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
    }

    /// 실측이 예측보다 절당 0.5pt 씩 크게 렌더된 상태를 만든다 (D9 R13 의 모양).
    /// 마지막 절의 Δ 가 한 줄(30pt)을 확실히 넘도록 절 수를 넉넉히 준다.
    private func measureWithAccumulatingDelta(_ store: StoreOf<CarveDetailFeature>, verseCount: Int = 80) {
        store.send(.view(.layoutHostingChanged(writingWidth: 372)))
        store.send(.setSentence(sentences(count: verseCount), []))
        var batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        for verse in 1...verseCount {
            batch[rowID(verse)] = VerseRowGeometry(underlineOffsets: [30])
        }
        store.send(.view(.verseGeometryMeasured(batch)))

        // 레이아웃은 예측(줄 수 × lineSpace)으로 지어졌고, 실제 행은 절당 0.5pt 씩 크다.
        // 실측 높이는 일부러 넣지 않는다 — R13 을 고치기 **전**의 어긋남을 재현해 안전망만 시험한다.
        let padding = ChapterLayoutHosting.firstVerseTopPadding
        var frames: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        var cursor = ChapterLayoutHosting.metrics.topInset
        for verse in 1...verseCount {
            if verse > 1 { cursor += ChapterLayoutHosting.metrics.verseSpacing }
            let height = (verse == 1 ? padding : 0) + 30 + 0.5
            frames[rowID(verse)] = VerseRowGeometry(rowFrame: CGRect(x: 10, y: cursor, width: 733, height: height))
            cursor += height
        }
        store.send(.view(.verseGeometryMeasured(frames)))
        // 캔버스 영역은 행 안 (0, 0) 에서 시작한다고 본다 — 높이는 여기서 넣지 않는다.
        var inner: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        for verse in 1...verseCount {
            let height = (verse == 1 ? padding : 0) + 30
            inner[rowID(verse)] = VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: height))
        }
        store.send(.view(.verseGeometryMeasured(inner)))
    }

    @Test("N-Canvas 경로에서는 Δ 가 한 줄을 넘어도 판정이 캔버스로 가지 않고 입력이 닫히지 않는다 (§14)")
    func nCanvasPathIsNeverBlockedByDelta() async throws {
        // ⚠️ 기본값에 기대지 않고 **명시적으로 flag 를 끈다.** 기본이 단일 Canvas 로 바뀌었으므로
        // (설계 §10-3 · `SingleCanvasFlag.defaultValue`) 예전처럼 initialState 를 쓰면 이 테스트가
        // 검증하려던 N-Canvas 경로를 타지 않는다.
        let suite = "CarveDetailDeltaGuard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SingleCanvasFlag.appStorageKey)

        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = CarveDetailFeature.State(headerState: .initialState)
            try #require(!state.usesSingleCanvas)
            let store = makeDetailStore(state)
            measureWithAccumulatingDelta(store)
            try await Task.sleep(for: .milliseconds(200))

            // 측정 자체는 "차단해야 할 크기" 라고 판정한다 — 즉 이 테스트는 Δ 가 작아서 통과하는 것이 아니다.
            let verdict = try #require(store.chapterLayout.layoutDeltaVerdict)
            #expect(verdict.blocksInput)
            #expect(verdict.magnitude > 30)

            // effect 를 실제로 태웠는데도 N-Canvas 경로에는 아무것도 전달되지 않았다.
            #expect(store.chapterCanvas.layoutDelta == nil)
            #expect(store.chapterCanvas.isDrawingInputEnabled == store.chapterCanvas.isInputEnabled)
            #expect(store.isLayoutReady)
        }
    }

    @Test("단일 Canvas 경로에서는 Δ 판정이 effect 로 캔버스까지 전달돼 새 입력이 닫힌다 (§14 안전망 배선)")
    func singleCanvasPathReceivesDeltaVerdict() async throws {
        let suite = "CarveDetailDeltaGuard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SingleCanvasFlag.appStorageKey)

        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let state = CarveDetailFeature.State(headerState: .initialState)
            try #require(state.usesSingleCanvas)
            let store = makeDetailStore(state)
            measureWithAccumulatingDelta(store)
            try await Task.sleep(for: .milliseconds(300))

            let verdict = try #require(store.chapterLayout.layoutDeltaVerdict)
            #expect(verdict.blocksInput)
            // `.layoutDeltaEvaluated` 를 손으로 보내지 않았다 — `forwardLayoutToSingleCanvas` 의 effect 가 옮긴 것이다.
            #expect(store.chapterCanvas.layoutDelta == verdict)
            #expect(!store.chapterCanvas.isDrawingInputEnabled)
        }
    }
}
