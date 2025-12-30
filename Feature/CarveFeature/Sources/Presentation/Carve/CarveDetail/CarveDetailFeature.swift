//
//  CarveDetailFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Resources
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct CarveDetailFeature {
    @ObservableState
    public struct State {
        /// 헤더 상태
        public var headerState: HeaderFeature.State
        /// 성경 구절 상태 List
        public var verseRowState: IdentifiedArrayOf<VerseRowFeature.State> = []
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
        /// ScrollView 위치 제어용 프록시
        public var proxy: ScrollViewProxy?
        /// 마지막으로 사용한 펜 종류(펜슬 더블탭시 전환용)
        var lastUsedPencil: PKInkingTool.InkType = .pencil
//        /// global 좌표계 기준 CombinedCanvasView의 frame (Canvas 기준 verse 별 rect 계산용)
//        var canvasGlobalFrame: CGRect = .zero
        
        /// 성경 문장 출력시 자간 폰트 등 설정
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        /// 왼손잡이용 레이아웃 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) var undoManager
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        /// 화면 최상단으로 스크롤
        case scrollToTop
        case setSentence([BibleVerse], [BibleDrawing])
        
        case view(View)
        case scope(ScopeAction)
        
        case setFetchedSentence(chapter: BibleChapter, verses: [BibleVerse])
        
        @CasePathable
        public enum View {
            /// 성경 구절 fetch
            case fetchSentence
            /// 스크롤에 따른 헤더 애니메이션
            case headerAnimation(CGFloat, CGFloat)
            /// scrollView proxy 설정
            case setProxy(ScrollViewProxy)
            /// 펜을 지우개로 전환
            case switchToEraser
            /// 펜 타입을 이전으로 전환
            case switchToPreviousPenType
            /// 캔버스 전체 프레임 변경
            case canvasFrameChanged(CGRect)
            /// 한 손가락 탭 액션: 헤더 노출/숨김
            case tapForHeaderHidden
            /// 두손가락 더블탭 액션: undo
            case twoFingerDoubleTapForUndo
            /// 밑줄 레이아웃 계산 (ForEachReducer missing element warning 회피를 위해 VerseRow가 아닌 상위에서 처리)
            case underlineLayoutChanged(id: VerseRowFeature.State.ID, layout: Text.LayoutKey.Value)
        }
    }

    @CasePathable
    public enum ScopeAction {
        case verseRowAction(IdentifiedActionOf<VerseRowFeature>)
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingFeature>)
        case headerAction(HeaderFeature.Action)
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

        Reduce { state, action in
            switch action {
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
                    let candidates = drawings.filter { $0.verse == sentence.verse && $0.lineData?.containsPKStroke == true }
                    let drawing = candidates.first(where: { $0.isPresent == true })
                    ?? candidates.sorted(by: { ($0.updateDate ?? Date.distantPast) > ($1.updateDate ?? Date.distantPast) }).first
                    sentenceState.append(SentencesWithDrawingFeature.State(sentence: sentence, drawing: drawing))
                }
                state.sentenceWithDrawingState = sentenceState
                undoManager.clear()
                return .none
                
            case .setFetchedSentence(let chapter, let verses):
                state.verseRowState = IdentifiedArrayOf(
                    uniqueElements: verses.map { VerseRowFeature.State(sentence: $0) }
                )
                
//                state.canvasState = .init(chapter: chapter, drawingRect: [:])
                
                // 3) Drawing 데이터 fetch 트리거
//                return .send(.scope(.canvasAction(.fetchDrawingData)))
                return .none

            case .view(.underlineLayoutChanged(let id, let layout)):
                guard var row = state.sentenceWithDrawingState[id: id] else { return .none }

                let setting = row.sentenceState.sentenceSetting
                let offsets = VerseTextFeature.makeUnderlineOffsets(
                    from: layout,
                    sentenceSetting: setting
                )
                row.sentenceState.underlineOffsets = offsets
                state.sentenceWithDrawingState[id: id] = row

                return .none
                
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
                return .send(.scope(.headerAction(.toggleVisibility)))
                
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
                let sentenceState = state.sentenceWithDrawingState[index]
                return .run { _ in
                    guard let drawing = sentenceState.canvasState.drawing,
                          drawing.lineData?.containsPKStroke == true
                    else { return }
                    try await drawingContext.updateDrawing(drawing: drawing)
                }
                
                     
            default: return .none
            }
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            SentencesWithDrawingFeature()
        }
    }
    
    
    enum CarveReducerError: Error {
        case fetchSentenceError
        case chapterConvertError
    }
}


extension CarveDetailFeature {
    /// 성경 본문 가져오기
    /// - Parameter chapter: 가져올 성경의 제목과 장
    private func fetchBible(chapter: BibleChapter) throws(CarveReducerError) -> [BibleVerse] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [BibleVerse] = []
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else { return sentences}
        do {
            let bible = try String(contentsOfFile: textPath,
                                   encoding: String.Encoding(rawValue: encodingEUCKR))
            sentences = try bible.components(separatedBy: "\r")
                .filter {
                    guard let num = $0.components(separatedBy: ":").first,
                          let first = Int(num) else { throw CarveReducerError.chapterConvertError }
                    return first == chapter.chapter
                }
                .map { sentence in
                    return BibleVerse.init(title: chapter, sentence: sentence)
                }
        } catch {
            throw .fetchSentenceError
        }
        return sentences
    }
    
    
    /// 1. 성경 본문 fetch
    /// 2. sentenceWithDrawingState 및 canvasState 초기화,
    /// 3. Drawing데이터 불러옴
    private func handleFetchSentence(state: inout State) -> Effect<Action> {
        let title = state.headerState.currentTitle
          
        return .run { send in
            do {
                let sentences = try fetchBible(chapter: title)
                let drawings = try await drawingContext.fetch(chapter: title)
                
                try Task.checkCancellation()
                await send(.setSentence(sentences, drawings))
                
 //                await send(.setFetchedSentence(chapter: title, verses: sentences))
            } catch {
                Log.error("Fetch Sentence Error")
            }
        }
        .cancellable(id: CancelID.fetchBible(title: title), cancelInFlight: true)
    }
    
    
    /// ScrollView 맨 위로 스크롤
    private func scrollToTop(state: inout State) -> Effect<Action> {
        guard let id = state.verseRowState.first?.id else { return .none }
        withAnimation(.easeInOut(duration: 0.5)) {
            state.proxy?.scrollTo(id, anchor: .bottom)
        }
        return .none
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
