//
//  CarveDetailReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import Foundation
import Resources

import ComposableArchitecture

@Reducer
public struct CarveDetailReducer {
    @ObservableState
    public struct State {
        public var headerState: HeaderReducer.State
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
        @Presents var navigation: Destination.State?
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext

    
    public enum Action: FeatureAction, Core.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    @CasePathable
    public enum ViewAction {
        case headerAnimation(CGFloat, CGFloat)
        case navigation(PresentationAction<Destination.Action>)
        case setTitle(TitleVO)
    }
    public enum InnerAction {
        case fetchSentence
        case setSentence([SentenceVO], [DrawingVO])
    }
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingReducer>)
        case headerAction(HeaderReducer.Action)
    }
    @Reducer
    public enum Destination {
        case sentenceSettings(SentenceSettingsReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                return .run { send in
                    await send(.scope(.headerAction(.headerAnimation(previous, current))))
                }
            case .inner(.fetchSentence):
                let title = state.headerState.currentTitle
                let sentences = fetchBible(chapter: title)
                return .run { send in
                    do {
                        var storedDrawing = try await drawingContext.fetch(title: title)
                        guard let lastSection = sentences.last?.section
                        else {
                            throw CarveReducerError.fetchSentenceError
                        }
                        if storedDrawing.count != sentences.count {
                            try await drawingContext.setDrawing(title: title, to: lastSection)
                            storedDrawing = try await drawingContext.fetch(title: title)
                        }
                        await send(.inner(.setSentence(sentences, storedDrawing)))
                    } catch {
                        Log.debug("fetch drawing error", error)
                        await send(.inner(.setSentence(sentences, [])))
                    }
                }
            case .inner(.setSentence(let sentences, let drawings)):
                state.sentenceWithDrawingState.removeAll()
                for (index, sentence) in sentences.enumerated() {
                    let drawing = (drawings.isEmpty)
                    ? DrawingVO(bibleTitle: sentence.title, section: sentence.section)
                    : drawings[index]
                    let currentState = SentencesWithDrawingReducer.State(sentence: sentence, drawing: drawing)
                    state.sentenceWithDrawingState.append(currentState)
                }
            case .view(.setTitle(let title)):
                return .run { send in
                    await send(.scope(.headerAction(.setCurrentTitle(title))))
                    await send(.inner(.fetchSentence))
                }
            case .scope(.headerAction(.pencilConfigDidTapped)):
                Log.debug("pencilConfigDidTapped")
            case .scope(.headerAction(.sentenceSettingsDidTapped)):
                state.navigation = .sentenceSettings(.initialState)
            default: break
            }
            return .none
        }
        .ifLet(\.$navigation, action: \.view.navigation)
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            SentencesWithDrawingReducer()
        }
    }
    
    
    private func fetchBible(chapter: TitleVO) -> [SentenceVO] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [SentenceVO] = []
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else { return sentences}
        
        do {
            let bible = try String(contentsOfFile: textPath,
                                   encoding: String.Encoding(rawValue: encodingEUCKR))
            sentences = bible.components(separatedBy: "\r")
                .filter {
                    Int($0.components(separatedBy: ":").first!)! == chapter.chapter
                }
                .map { sentence in
                    return SentenceVO.init(title: chapter, sentence: sentence)
                }
        } catch let error {
            Log.error(error.localizedDescription)
        }
        return sentences
    }
    
    
    private enum CarveReducerError: Error {
        case fetchSentenceError
    }
}
