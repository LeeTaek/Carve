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
        public var sentenceWithDrawingState: IdentifiedArrayOf<VerseRowFeature.State> = []
        /// 캔버스 상태
        public var canvasState: CombinedCanvasFeature.State = .initialState
        /// ScrollView 위치 제어용 프록시
        public var proxy: ScrollViewProxy?
        /// 마지막으로 사용한 펜 종류(펜슬 더블탭시 전환용)
        var lastUsedPencil: PKInkingTool.InkType = .pencil
        /// global 좌표계 기준 CombinedCanvasView의 frame (Canvas 기준 verse 별 rect 계산용)
        var canvasGlobalFrame: CGRect = .zero
        
        /// 성경 문장 출력시 자간 폰트 등 설정
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        /// 왼손잡이용 레이아웃 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        /// 화면 최상단으로 스크롤
        case scrollToTop
        case view(View)
        case scope(ScopeAction)
        
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
        }
    }

    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<VerseRowFeature>)
        case headerAction(HeaderFeature.Action)
        case canvasAction(CombinedCanvasFeature.Action)
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderFeature()
        }
        Scope(state: \.canvasState,
              action: \.scope.canvasAction) {
            CombinedCanvasFeature()
        }

        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                return .send(.scope(.headerAction(.headerAnimation(previous, current))))
                
            case .view(.fetchSentence):
                return handleFetchSentence(state: &state)
                
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

            case .scope(.sentenceWithDrawingAction(
                .element(id: let id, action: .view(.updateVerseFrame(let globalRect))))
            ):
                return updateVerseFrame(
                    state: &state,
                    id: id,
                    globalRect: globalRect
                )
                
            case .view(.canvasFrameChanged(let rect)):
                state.canvasGlobalFrame = rect
                return .none

            case .scope(.canvasAction(.undoStateChanged(let canUndo, let canRedo))):
                state.headerState.palatteSetting.canUndo = canUndo
                state.headerState.palatteSetting.canRedo = canRedo
                return .none

            case .scope(.headerAction(.palatteAction(.view(.undo)))):
                return .send(.scope(.canvasAction(.undo)))
                
            case .scope(.headerAction(.palatteAction(.view(.redo)))):
                return .send(.scope(.canvasAction(.redo)))
                
            case .view(.tapForHeaderHidden):
                return .send(.scope(.headerAction(.toggleVisibility)))
                
            case .view(.twoFingerDoubleTapForUndo):
                return .send(.scope(.canvasAction(.undo)))
                
            default: return .none
            }
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            VerseRowFeature()
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
    private func fetchBible(chapter: TitleVO) throws(CarveReducerError) -> [SentenceVO] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [SentenceVO] = []
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
                    return SentenceVO.init(title: chapter, sentence: sentence)
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
          var sentenceState: IdentifiedArrayOf<VerseRowFeature.State> = []
          
          do {
              let sentences = try fetchBible(chapter: title)
              sentences.forEach {
                  sentenceState.append(VerseRowFeature.State(sentence: $0))
              }
              state.sentenceWithDrawingState = sentenceState
              state.canvasState = .init(title: title, drawingRect: [:])
              return .send(.scope(.canvasAction(.fetchDrawingData)))
          } catch {
              Log.error("Fetch Sentence Error")
              return .none
          }
    }
    
    
    /// ScrollView 맨 위로 스크롤
    private func scrollToTop(state: inout State) -> Effect<Action> {
        guard let id = state.sentenceWithDrawingState.first?.id else { return .none }
        withAnimation(.easeInOut(duration: 0.5)) {
            state.proxy?.scrollTo(id, anchor: .bottom)
        }
        return .none
    }
    
    
    /// Sentence 셀에서 전달된 global 좌표를 Canvas 기준 로컬 좌표로 변환하고,
    /// 각 절의 rect를 CombinedCanvasFeature에 전달.
    /// - Parameters:
    ///   - id: 각 절의 상태 ID
    ///   - globalRect: 각 절의 Rect
    private func updateVerseFrame(
        state: inout State,
        id: VerseRowFeature.State.ID,
        globalRect: CGRect
    ) -> Effect<Action> {
        guard let index = state.sentenceWithDrawingState.firstIndex(where: { $0.id == id }) else {
            return .none
        }
        let sentenceState = state.sentenceWithDrawingState[index]
        let verse = sentenceState.sentence.verse

        let canvasFrame = state.canvasGlobalFrame
        guard canvasFrame.width > 0, canvasFrame.height > 0 else { return .none }

        // canvas 기준 로컬 rect로 변환
        let localRect = CGRect(
            x: globalRect.minX - canvasFrame.minX,
            y: globalRect.minY - canvasFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )

        return .send(.scope(.canvasAction(
            .verseFrameUpdated(verse: verse, rect: localRect)
        )))
    }
}
