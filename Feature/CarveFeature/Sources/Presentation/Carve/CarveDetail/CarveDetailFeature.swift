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
        public var proxy: ScrollViewProxy?
        public var firstItemID: ObjectIdentifier?
        public static let initialState = State(
            headerState: .initialState
        )
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        var lastUsedPencil: PKInkingTool.InkType = .pencil
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) var undoManager
    
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
        }
    }

    public enum InnerAction {
        case setSentence([SentenceVO], [BibleDrawing])
        case scrollToTop
    }
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingFeature>)
        case headerAction(HeaderFeature.Action)
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                return .run { send in
                    await send(.scope(.headerAction(.headerAnimation(previous, current))))
                }
            case .view(.fetchSentence):
                let title = state.headerState.currentTitle
                return .run { send in
                    let sentences = try fetchBible(chapter: title)
                    do {
                        let storedDrawing = try await drawingContext.fetch(title: title)
                        await send(.inner(.setSentence(sentences, storedDrawing)))
                    } catch {
                        Log.error("fetch drawing error", error)
                        await send(.inner(.setSentence([], [])))
                    }
                }
            case .inner(.setSentence(let sentences, let drawings)):
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
                for sentence in sentences {
                    let candidates = drawings.filter { $0.verse == sentence.verse && $0.lineData?.containsPKStroke == true }
                    let drawing = candidates.first(where: { $0.isPresent == true })
                    ?? candidates.sorted(by: { ($0.updateDate ?? Date.distantPast) > ($1.updateDate ?? Date.distantPast) }).first
                    sentenceState.append(SentencesWithDrawingFeature.State(sentence: sentence, drawing: drawing))
                }
                state.sentenceWithDrawingState = sentenceState
                undoManager.clear()
            case .view(.setProxy(let proxy)):
                state.proxy = proxy
                return .run { send in
                    await send(.inner(.scrollToTop))
                }
            case .inner(.scrollToTop):
                guard let id = state.sentenceWithDrawingState.first?.id else { return .none }
                withAnimation(.easeInOut(duration: 0.5)) {
                    state.proxy?.scrollTo(id, anchor: .bottom)
                }
            case .scope(.sentenceWithDrawingAction(.element(id: let id,
                                                            action: .scope(.canvasAction(let action))))):
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
            case .view(.switchToEraser):
                // monoline을 지우개로 사용
                Log.debug("switch Eraser")
                state.lastUsedPencil = state.headerState.palatteSetting.pencilConfig.pencilType
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(.monoline))))))
            case .view(.switchToPrevious):
                Log.debug("switch previous")
                // 지우개인 경우 기본 펜으로
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(state.lastUsedPencil))))))
                
            case .scope(.headerAction(.palatteAction(.view(.setPencilType(let penType))))):
                guard penType != .monoline,
                      penType != state.lastUsedPencil
                else { return .none }
                
                state.lastUsedPencil = penType
            default: break
            }
            return .none
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            SentencesWithDrawingFeature()
        }
    }
    
    
    func fetchBible(chapter: TitleVO) throws(CarveReducerError) -> [SentenceVO] {
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
    
    
    enum CarveReducerError: Error {
        case fetchSentenceError
        case chapterConvertError
    }
}
