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
        public var headerState: HeaderFeature.State
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
        public var canvasState: CombinedCanvasFeature.State = .initialState
        public var proxy: ScrollViewProxy?
        
        public static let initialState = State(
            headerState: .initialState
        )
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        var lastUsedPencil: PKInkingTool.InkType = .pencil
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        case view(View)
        case inner(InnerAction)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            case fetchSentence
            case headerAnimation(CGFloat, CGFloat)
            case setProxy(ScrollViewProxy)
            case switchToEraser
            case switchToPrevious
            case canvasFrameChanged(CGRect)
        }
    }

    public enum InnerAction {
        case scrollToTop
    }
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingFeature>)
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
                let title = state.headerState.currentTitle
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
                
                guard let sentences = try? fetchBible(chapter: title) else {
                    Log.error("Fetch Sentence Error")
                    return .none
                }
                sentences.forEach {
                    sentenceState.append(SentencesWithDrawingFeature.State(sentence: $0))
                }
                state.sentenceWithDrawingState = sentenceState
                state.canvasState = .init(title: title, drawingRect: [:])
                
                return .send(.scope(.canvasAction(.fetchDrawingData)))
                
            case .view(.setProxy(let proxy)):
                state.proxy = proxy
                return .send(.inner(.scrollToTop))
                
            case .inner(.scrollToTop):
                guard let id = state.sentenceWithDrawingState.first?.id else { return .none }
                withAnimation(.easeInOut(duration: 0.5)) {
                    state.proxy?.scrollTo(id, anchor: .bottom)
                }

            case .view(.switchToEraser):
                // monoline을 지우개로 사용
                Log.debug("switch Eraser")
                state.lastUsedPencil = state.headerState.palatteSetting.pencilConfig.pencilType
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(.monoline))))))
                
            case .view(.switchToPrevious):
                // 지우개인 경우 기본 펜으로
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(state.lastUsedPencil))))))
                
            case .scope(.headerAction(.palatteAction(.view(.setPencilType(let penType))))):
                guard penType != .monoline,
                      penType != state.lastUsedPencil
                else { return .none }
                
                state.lastUsedPencil = penType
                
            case .scope(.sentenceWithDrawingAction(
                .element(id: let id, action: .view(.updateVerseFrame(let globalRect))))
            ):
                guard let index = state.sentenceWithDrawingState.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                let sentenceState = state.sentenceWithDrawingState[index]
                let verse = sentenceState.sentence.verse

                let canvasFrame = state.canvasState.canvasGlobalFrame
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
                
            case .view(.canvasFrameChanged(let rect)):
                return .send(.scope(.canvasAction(.canvasFrameChanged(rect))))
                
            case .scope(.canvasAction(.undoStateChanged(let canUndo, let canRedo))):
                state.headerState.palatteSetting.canUndo = canUndo
                state.headerState.palatteSetting.canRedo = canRedo
                
            case .scope(.headerAction(.palatteAction(.view(.undo)))):
                return .send(.scope(.canvasAction(.undo)))
                
            case .scope(.headerAction(.palatteAction(.view(.redo)))):
                return .send(.scope(.canvasAction(.redo)))
                
            default: break
            }
            return .none
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
}
