//
//  CarveDetailFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct CarveDetailFeature {
    @ObservableState
    public struct State {
        /// 헤더 상태
        public var headerState: HeaderFeature.State
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
        /// ScrollView 위치 제어용 프록시
        public var proxy: ScrollViewProxy?
        /// 차트 등 외부 화면에서 특정 절로 이동할 때 사용할 스크롤 타깃 ID.
        public var scrollTargetID: SentencesWithDrawingFeature.State.ID?
        /// 마지막으로 사용한 펜 종류(펜슬 더블탭시 전환용)
        var lastUsedPencil: PKInkingTool.InkType = .pencil
//        /// global 좌표계 기준 CombinedCanvasView의 frame (Canvas 기준 verse 별 rect 계산용)
//        var canvasGlobalFrame: CGRect = .zero

        /// Phase 2 — 장 전체 레이아웃 측정 상태 (설계 §6). 절별 실측이 모이면 `ChapterLayout` 이 완성된다.
        var chapterLayout = ChapterLayoutMeasurement()
        /// 설계 §6-2 입력 게이트. false 인 동안 모든 절 캔버스의 펜 입력이 막힌다.
        public var isLayoutReady: Bool { chapterLayout.isReady }
        /// 진행 중인 측정 구간의 `os_signpost` ID (`ChapterLayoutSignpost`).
        var layoutSignpostID: UInt64?
        /// 마지막으로 편집(획 추가/지우개)이 올라온 절. 디버그 오버레이의 dirtyBounds 표시용.
        var lastEditedVerseID: SentencesWithDrawingFeature.State.ID?

        // MARK: Phase 3 — feature flag 뒤 단일 Canvas (설계 §13 Phase 3)

        /// 단일 Canvas 경로 사용 여부. 기본 off — flag off 가 §10-3 의 유일한 롤백 수단이다.
        /// 설정 > 필사 캔버스 의 토글(`CanvasSettingsFeature`)이 같은 키에 쓴다. Debug 실행 인자 `-SingleCanvas` 도 같은 효과다.
        @Shared(.appStorage(SingleCanvasFlag.appStorageKey))
        public var isSingleCanvasEnabled: Bool = SingleCanvasFlag.defaultValue
        /// 단일 Canvas 상태. flag off 일 때는 아무 액션도 받지 않는다.
        var chapterCanvas = ChapterCanvasFeature.State(chapter: .initialState)
        /// 외부 진입(차트 등)으로 이동할 절 번호. 단일 Canvas 는 `ScrollViewProxy` 가 없어 절 번호로 스크롤한다.
        var scrollTargetVerse: Int?
        /// 단일 Canvas 의 절 필사 기록 시트 (§8-7 히스토리 UI, B 구조). 롱프레스 → `ChapterCanvasFeature.Delegate.showHistory` 로 연다.
        @Presents var chapterHistory: VerseDrawingHistoryFeature.State?

        /// flag 또는 Debug 실행 인자로 단일 Canvas 를 쓸지.
        public var usesSingleCanvas: Bool {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(SingleCanvasFlag.debugLaunchArgument) { return true }
            #endif
            return isSingleCanvasEnabled
        }
        
        /// 성경 문장 출력시 자간 폰트 등 설정
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        /// 왼손잡이용 레이아웃 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.bibleTextClient) var bibleTextClient
    @Dependency(\.undoManager) var undoManager
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        /// 화면 최상단으로 스크롤
        case scrollToTop
        case setSentence([BibleVerse], [BibleDrawing])
        case setScrollTarget(BibleVerse)
        /// 단일 Canvas 의 절 필사 기록 시트.
        case chapterHistory(PresentationAction<VerseDrawingHistoryFeature.Action>)
        
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            /// 성경 구절 fetch
            case fetchSentence
            #if DEBUG
            /// HUD가 나타나거나 표시할 진단 값이 바뀌었을 때 콘솔에 기록한다.
            case debugHUDSnapshotChanged(String)
            #endif
            /// 스크롤에 따른 헤더 애니메이션
            case headerAnimation(CGFloat, CGFloat)
            /// scrollView proxy 설정
            case setProxy(ScrollViewProxy)
            /// 펜을 지우개로 전환
            case switchToEraser
            /// 펜 타입을 이전으로 전환
            case switchToPreviousPenType
            /// 한 손가락 탭 액션: 헤더 펼침/축소
            case tapForHeaderHidden
            /// 두손가락 더블탭 액션: undo
            case twoFingerDoubleTapForUndo
            /// 여러 행의 실측값(밑줄 offset · 소제목 높이 · 캔버스 frame)을 **한 번에** 반영 (Phase 2 — 설계 §6).
            ///
            /// 행마다 액션을 보내면 안 된다 — 액션 하나가 부모 상태를 바꿔 스코프 스토어 전체와 `VStack` 전체 패스를
            /// 다시 돌리므로 행 수의 제곱으로 비용이 늘어난다 (`VerseGeometryCollector` 참조).
            /// 밑줄 offset 을 여기서(행이 아닌 상위에서) 반영하는 것은 ForEachReducer missing element warning 회피이기도 하다.
            case verseGeometryMeasured([VerseRowFeature.State.ID: VerseRowGeometry])
            /// 필사 컬럼 폭이 바뀜 (Phase 2 — `ChapterLayout.writingWidth`)
            case layoutHostingChanged(writingWidth: CGFloat)
            /// 앱이 비활성/백그라운드로 감 — 단일 Canvas 의 미저장분을 저장한다 (§8-5, best-effort)
            case appWillResignActive
        }
    }

    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingFeature>)
        case headerAction(HeaderFeature.Action)
        /// Phase 3 — 단일 Canvas
        case chapterCanvasAction(ChapterCanvasFeature.Action)
//        case canvasAction(CombinedCanvasFeature.Action)
    }
    
    /// 비동기 작업 취소용 작업
    enum CancelID: Hashable {
        /// 성경 불러올떄
        case fetchBible(title: BibleChapter)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderFeature()
        }
        Scope(state: \.chapterCanvas,
              action: \.scope.chapterCanvasAction) {
            ChapterCanvasFeature()
        }

        Reduce { state, action in
            switch action {
            #if DEBUG
            case .view(.debugHUDSnapshotChanged(let snapshot)):
                return .run { _ in
                    print("ChapterHUD \(snapshot)")
                }
            #endif
            case .view(.headerAnimation(let previous, let current)):
                return .send(.scope(.headerAction(.headerAnimation(previous, current))))
                
            case .view(.fetchSentence):
                let oldChapter = state.headerState.currentTitle
                                
                return .merge(
                    .cancel(id: CancelID.fetchBible(title: oldChapter)),
                    handleFetchSentence(state: &state)
                )
                
            case .setSentence(let sentences, let drawings):
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
                for sentence in sentences {
                    // 획 유무로 후보를 거르지 않는다.
                    // 지우개로 전부 지운 절은 "stroke 0개인 유효한 drawing"으로 저장되는데,
                    // 여기서 걸러버리면 더 오래된(획이 남아 있는) 기록이 대표로 선택되어
                    // 지운 결과가 다시 살아난 것처럼 보인다.
                    // 대표 선택 규칙은 도메인의 `mainDrawing()`(isPresent 우선 → updateDate 최신)과 동일하게 맞춘다.
                    let candidates = drawings.filter { $0.verse == sentence.verse }
                    let drawing = candidates.first(where: { $0.isPresent == true })
                    ?? candidates.sorted(by: { ($0.updateDate ?? Date.distantPast) > ($1.updateDate ?? Date.distantPast) }).first
                    sentenceState.append(SentencesWithDrawingFeature.State(sentence: sentence, drawing: drawing))
                }
                state.sentenceWithDrawingState = sentenceState
                undoManager.clear()
                beginLayoutMeasurement(state: &state, sentences: sentences)
                // 단일 Canvas 면 팔레트의 undo/redo 는 캔버스가 처리한다 — 팔레트가 SharedUndoManager 값으로 공유 canUndo 를 덮지 않게.
                state.headerState.palatteSetting.delegatesUndoToCanvas = state.usesSingleCanvas
                state.chapterHistory = nil
                guard state.usesSingleCanvas else {
                    // flag 를 끄고 돌아온 장 — 단일 Canvas 에 남은 미저장분은 여기서 마저 저장한다 (§8-5).
                    return state.chapterCanvas.isFullyPersisted ? .none : .send(.scope(.chapterCanvasAction(.flushPending)))
                }
                // 단일 Canvas: 본문이 확정된 시점에 조회를 시작한다 (§6-4). 레이아웃은 실측이 끝나면 따로 들어간다.
                let chapter = sentences.first?.title ?? state.headerState.currentTitle
                return .send(.scope(.chapterCanvasAction(.load(chapter: chapter, expectedVerseCount: sentences.count))))
                
            case .setScrollTarget(let verse):
                state.scrollTargetID = makeSentenceID(for: verse)
                state.scrollTargetVerse = verse.verse
                return .none
                
            case .view(.verseGeometryMeasured(let batch)):
                applyVerseGeometry(state: &state, batch: batch)
                return forwardLayoutToSingleCanvas(state: &state)

            case .view(.layoutHostingChanged(let writingWidth)):
                if state.chapterLayout.setWritingWidth(writingWidth) {
                    rebuildLayoutIfNeeded(state: &state)
                }
                return forwardLayoutToSingleCanvas(state: &state)

            case .view(.appWillResignActive):
                // flag 와 무관하게 보낸다 — 방금 flag 를 끈 뒤에도 단일 Canvas 에 미저장분이 남아 있을 수 있다. 없으면 no-op.
                return .send(.scope(.chapterCanvasAction(.flushPending)))

            case .scope(.chapterCanvasAction(.delegate(.showHistory(let verse)))):
                state.chapterHistory = VerseDrawingHistoryFeature.State(title: state.chapterCanvas.chapter, verse: verse)
                return .none

            case .chapterHistory(.presented(.setPresentDrawing(let drawing))):
                // §8-7 복원 흐름 — ② isPresent 이전은 시트가 이미 DB 에 반영했다. ③ mutation 없이 다시 합성하며,
                // 그 안에서 ① 미저장분이 먼저 저장된다 (rowID 주소지정이라 이전 활성 행의 변경도 유실되지 않는다).
                guard let verse = state.chapterHistory?.verse else { return .none }
                state.chapterHistory = nil
                return .send(.scope(.chapterCanvasAction(
                    .verseRowRestored(verse: drawing.verse ?? verse, rowID: BibleDrawingRowID(raw: drawing.rowKey))
                )))

            case .scope(.headerAction(.palatteAction(.view(.undo)))):
                guard state.usesSingleCanvas else { return .none }
                return .send(.scope(.chapterCanvasAction(.undoTapped)))

            case .scope(.headerAction(.palatteAction(.view(.redo)))):
                guard state.usesSingleCanvas else { return .none }
                return .send(.scope(.chapterCanvasAction(.redoTapped)))
                
            case .view(.setProxy(let proxy)):
                state.proxy = proxy
                return .send(.scrollToTop)
                
            case .scrollToTop:
                return scrollToTop(state: &state)

            case .view(.switchToEraser):
                // monoline을 지우개로 사용
                state.lastUsedPencil = state.headerState.palatteSetting.pencilConfig.pencilType
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(.monoline))))))
                
            case .view(.switchToPreviousPenType):
                // 지우개인 경우 기본 펜으로
                return .send(
                    .scope(.headerAction(.palatteAction(.view(.setPencilType(state.lastUsedPencil)))))
                )
                
            case .scope(.headerAction(.palatteAction(.view(.setPencilType(let penType))))):
                guard penType != .monoline,
                      penType != state.lastUsedPencil
                else { return .none }
                
                state.lastUsedPencil = penType
                return .none

//            case .scope(.verseRowAction(
//                .element(id: let id, action: .view(.updateVerseFrame(let globalRect))))
//            ):
//                return updateVerseFrame(
//                    state: &state,
//                    id: id,
//                    globalRect: globalRect
//                )
//                
//            case .view(.canvasFrameChanged(let rect)):
//                state.canvasGlobalFrame = rect
//                return .none
//
//            case .scope(.canvasAction(.undoStateChanged(let canUndo, let canRedo))):
//                state.headerState.palatteSetting.canUndo = canUndo
//                state.headerState.palatteSetting.canRedo = canRedo
//                return .none
//            case .scope(.headerAction(.palatteAction(.view(.undo)))):
//                return .send(.scope(.canvasAction(.undo)))
//                return .none
//                
//            case .scope(.headerAction(.palatteAction(.view(.redo)))):
//                return .send(.scope(.canvasAction(.redo)))
            
            case .view(.tapForHeaderHidden):
                return .send(.scope(.headerAction(.toggleCompact)))
                
            case .view(.twoFingerDoubleTapForUndo):
//                return .send(.scope(.canvasAction(.undo)))
                Log.debug("두손가락 탭")
                return .send(.scope(.headerAction(.palatteAction(.view(.undo)))))

            case .scope(.sentenceWithDrawingAction(
                .element(id: let id,
                         action: .scope(.canvasAction(let action))))
            ):
                guard case .saveDrawing = action,
                      let index = state.sentenceWithDrawingState.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                state.lastEditedVerseID = id
                let drawing = state.sentenceWithDrawingState[index].canvasState.drawing
                return .run { _ in
                    try await persistDrawing(drawing)
                }
                
                     
            default: return .none
            }
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            SentencesWithDrawingFeature()
        }
        .ifLet(\.$chapterHistory, action: \.chapterHistory) {
            VerseDrawingHistoryFeature()
        }
    }
}


extension CarveDetailFeature {
    /// Canvas에서 올라온 변경(획 추가 / 지우개)을 SwiftData에 반영.
    ///
    /// - Important: 획 유무를 조건으로 걸지 않는다.
    ///   `PKEraserTool(.bitmap)`으로 마지막 획까지 지우면 그 stroke는 `PKDrawing.strokes`에서 제거되어
    ///   `lineData?.containsPKStroke == false`가 된다. 예전에는 이 조건을 저장의 전제로 삼아
    ///   "전부 지운 순간"의 저장이 통째로 건너뛰어졌고, 앱을 재기동하면 지웠던 획이 되살아났다.
    ///   따라서 stroke가 0개인 drawing도 그대로 저장한다.
    func persistDrawing(_ drawing: BibleDrawing?) async throws {
        guard let drawing else { return }
        try await drawingContext.updateDrawing(drawing: drawing)
    }

    /// `SentencesWithDrawingFeature.State.id` 규칙과 동일한 스크롤용 ID를 생성.
    private func makeSentenceID(for verse: BibleVerse) -> SentencesWithDrawingFeature.State.ID {
        "\(verse.title.title.koreanTitle()).\(verse.title.chapter).\(verse.verse)"
    }

    // MARK: - Phase 2 — 장 레이아웃 측정 (설계 §6)

    /// 새 장의 본문이 확정된 시점에 측정을 시작한다. 이전 장의 실측값은 전부 버린다.
    ///
    /// `expectedVerseCount` 는 여기서 확정된 절 개수이며(§6-4), 게이트는 이 값과 완성된 레이아웃의 절 수를 비교한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - sentences: fetch 된 본문.
    private func beginLayoutMeasurement(state: inout State, sentences: [BibleVerse]) {
        let chapter = sentences.first?.title ?? state.headerState.currentTitle
        var savedBandCounts: [Int: Int] = [:]
        for row in state.sentenceWithDrawingState {
            if let count = Self.savedBandCount(of: row.canvasState.drawing) {
                savedBandCounts[row.sentence.verse] = count
            }
        }
        state.chapterLayout.begin(
            chapter: chapter,
            verses: sentences.map(\.verse),
            savedBandCounts: savedBandCounts,
            now: ContinuousClock().now
        )
        state.layoutSignpostID = ChapterLayoutSignpost.beginMeasure(chapter: chapter, verseCount: sentences.count)
        // 폭은 장이 바뀌어도 그대로이므로 이미 알고 있으면 곧바로 계산 조건에 포함된다.
        rebuildLayoutIfNeeded(state: &state)
    }

    /// 행들의 실측값을 한 번에 반영한다.
    ///
    /// 이전 장의 행에서 늦게 도착한 값은 id 조회에 실패해 버려진다 (설계 §6-4 의 요청 취소).
    /// 레이아웃 재계산은 배치 전체를 반영한 뒤 **한 번만** 한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - batch: 행 id → 실측값.
    private func applyVerseGeometry(state: inout State, batch: [VerseRowFeature.State.ID: VerseRowGeometry]) {
        var layoutInputChanged = false
        for (id, geometry) in batch {
            guard var row = state.sentenceWithDrawingState[id: id] else { continue }
            let verse = row.sentence.verse

            if let offsets = geometry.underlineOffsets {
                // 밑줄은 캔버스 영역 안에서 1절의 상단 여백만큼 내려 그려지므로, 레이아웃 anchor 도 같은 값을 더한다.
                let anchors = offsets.map { $0 + ChapterLayoutHosting.topPadding(forVerse: verse) }
                // 절 캔버스의 첫 밑줄 y — 단일 Canvas 가 첫 밑줄 원점(v3)으로 저장한 행을 N-Canvas 가 제자리에 보이게 하는 기준 (§10-3 flag off).
                let firstUnderlineY = anchors.first ?? 0
                if row.sentenceState.underlineOffsets != offsets || row.canvasState.firstUnderlineY != firstUnderlineY {
                    row.sentenceState.underlineOffsets = offsets
                    row.canvasState.firstUnderlineY = firstUnderlineY
                    state.sentenceWithDrawingState[id: id] = row
                }
                if state.chapterLayout.recordText(verse: verse, underlineAnchors: anchors) {
                    layoutInputChanged = true
                }
            }
            if let height = geometry.titleHeight,
               state.chapterLayout.recordTitleHeight(verse: verse, height: height) {
                layoutInputChanged = true
            }
            // 행 frame 은 원점만 쓰인다 (`columnOrigin` · Δ 의 topDelta). 검증 전용이라 재계산 조건에 넣지 않는다.
            if let frame = geometry.rowFrame {
                state.chapterLayout.recordRowFrame(verse: verse, frame: frame)
            }
            // 행 안 캔버스 영역의 **높이**는 레이아웃 입력이다 (R13 — `VerseLayoutInput.measuredHeight`).
            // 빌더의 `줄 수 × lineSpace` 예측이 실기기에서 절당 0.5pt 씩 어긋나 누적됐으므로 실측을 쓴다.
            // 따라서 재계산 조건에 **포함한다** — 예측으로 지은 레이아웃이 실측이 도착하면 다시 지어진다.
            if let frame = geometry.canvasFrameInRow,
               state.chapterLayout.recordCanvasFrameInRow(verse: verse, frame: frame) {
                layoutInputChanged = true
            }
        }
        if layoutInputChanged {
            rebuildLayoutIfNeeded(state: &state)
        }
    }

    /// 입력이 전부 모였으면 레이아웃을 (재)계산하고 계측을 남긴다.
    /// - Parameter state: Feature 상태.
    private func rebuildLayoutIfNeeded(state: inout State) {
        let wasBuilt = state.chapterLayout.buildCount > 0
        guard let layout = state.chapterLayout.rebuildIfComplete(
            setting: state.sentenceSetting,
            isLeftHanded: state.isLeftHanded,
            metrics: ChapterLayoutHosting.metrics,
            now: ContinuousClock().now
        ) else { return }

        if wasBuilt {
            ChapterLayoutSignpost.rebuildEvent(layout: layout, buildCount: state.chapterLayout.buildCount)
            return
        }
        if let signpostID = state.layoutSignpostID, let duration = state.chapterLayout.firstBuildDuration {
            ChapterLayoutSignpost.endMeasure(rawID: signpostID, layout: layout, duration: duration)
            state.layoutSignpostID = nil
            Log.info("ChapterLayout 완성", "\(layout.chapter.title.rawValue).\(layout.chapter.chapter)",
                     "\(layout.regions.count)절", "H=\(layout.totalHeight)", "\(duration)")
        }
    }

    /// 저장된 필사의 band 수 (설계 §6-3 의 `N_saved`). metadata 가 없는 legacy 행이면 nil.
    /// - Parameter drawing: 절의 대표 행.
    /// - Returns: band 수.
    static func savedBandCount(of drawing: BibleDrawing?) -> Int? {
        guard let data = drawing?.layoutMetadataData,
              let metadata = try? JSONDecoder().decode(DrawingLayoutMetadata.self, from: data) else {
            return nil
        }
        return metadata.savedBandCount
    }
    
    /// 1. 성경 본문 fetch
    /// 2. sentenceWithDrawingState 및 canvasState 초기화,
    /// 3. Drawing데이터 불러옴
    private func handleFetchSentence(state: inout State) -> Effect<Action> {
        let title = state.headerState.currentTitle
          
        return .run { send in
            do {
                let sentences = try bibleTextClient.fetch(chapter: title)
                let drawings = try await drawingContext.fetch(chapter: title)
                
                try Task.checkCancellation()
                await send(.setSentence(sentences, drawings))
            } catch {
                Log.error("Fetch Sentence Error")
            }
        }
        .cancellable(id: CancelID.fetchBible(title: title), cancelInFlight: true)
    }
    
    
    /// ScrollView 맨 위로 스크롤
    private func scrollToTop(state: inout State) -> Effect<Action> {
        if state.usesSingleCanvas {
            let verse = state.scrollTargetVerse ?? state.sentenceWithDrawingState.first?.sentence.verse
            state.scrollTargetID = nil
            state.scrollTargetVerse = nil
            guard let verse else { return .none }
            return .send(.scope(.chapterCanvasAction(.scrollToVerse(verse))))
        }
        let id = state.scrollTargetID ?? state.sentenceWithDrawingState.first?.id
        guard let id else { return .none }
        state.scrollTargetID = nil
        state.scrollTargetVerse = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            state.proxy?.scrollTo(id, anchor: .bottom)
        }
        return .none
    }

    /// Phase 3 — 완성된 `ChapterLayout` · `columnOrigin` · Δ 안전망 판정을 단일 Canvas 에 넘긴다. 값이 바뀐 것만 보낸다.
    ///
    /// `columnOrigin` 의 y 는 0 이다 — 헤더는 `contentInset.top` 으로 비우므로 콘텐츠 좌표는 헤더와 무관하다.
    ///
    /// **안전망은 단일 Canvas 경로에만 붙는다** (설계 §14 — D9 R13). 이 함수 자체가 `usesSingleCanvas` 로 막혀 있으므로
    /// N-Canvas 에서는 판정이 아예 나가지 않는다 — N-Canvas 는 절마다 자기 캔버스가 있고 잉크가 절-로컬이라
    /// 레이아웃 Δ 가 귀속을 틀지 않는다. 거기서 입력을 막으면 무해한 조건으로 필기를 못 하게 만드는 회귀다.
    private func forwardLayoutToSingleCanvas(state: inout State) -> Effect<Action> {
        guard state.usesSingleCanvas, let layout = state.chapterLayout.layout else { return .none }
        var effects: [Effect<Action>] = []
        if let origin = state.chapterLayout.columnOrigin,
           origin != state.chapterCanvas.columnOrigin, origin != state.chapterCanvas.pendingColumnOrigin {
            effects.append(.send(.scope(.chapterCanvasAction(.columnOriginChanged(origin)))))
        }
        if layout != state.chapterCanvas.layout && layout != state.chapterCanvas.pendingLayout {
            effects.append(.send(.scope(.chapterCanvasAction(.layoutCompleted(layout)))))
        }
        let verdict = state.chapterLayout.layoutDeltaVerdict
        if verdict != state.chapterCanvas.layoutDelta {
            effects.append(.send(.scope(.chapterCanvasAction(.layoutDeltaEvaluated(verdict)))))
        }
        return effects.isEmpty ? .none : .merge(effects)
    }
    
//    
//    /// Sentence 셀에서 전달된 global 좌표를 Canvas 기준 로컬 좌표로 변환하고,
//    /// 각 절의 rect를 CombinedCanvasFeature에 전달.
//    /// - Parameters:
//    ///   - id: 각 절의 상태 ID
//    ///   - globalRect: 각 절의 Rect
//    private func updateVerseFrame(
//        state: inout State,
//        id: VerseRowFeature.State.ID,
//        globalRect: CGRect
//    ) -> Effect<Action> {
//        guard let index = state.verseRowState.firstIndex(where: { $0.id == id }) else {
//            return .none
//        }
//        let sentenceState = state.verseRowState[index]
//        let verse = sentenceState.sentence.verse
//
//        let canvasFrame = state.canvasGlobalFrame
//        guard canvasFrame.width > 0, canvasFrame.height > 0 else { return .none }
//
//        // canvas 기준 로컬 rect로 변환
//        let localRect = CGRect(
//            x: globalRect.minX - canvasFrame.minX,
//            y: globalRect.minY - canvasFrame.minY,
//            width: globalRect.width,
//            height: globalRect.height
//        )
//
//        return .send(.scope(.canvasAction(
//            .verseFrameUpdated(verse: verse, rect: localRect)
//        )))
//    }
}
