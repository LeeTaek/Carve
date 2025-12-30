//
//  SentencesWithDrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentencesWithDrawingFeature {
    @ObservableState
    public struct State: Identifiable, Equatable {
        public static func == (lhs: SentencesWithDrawingFeature.State, rhs: SentencesWithDrawingFeature.State) -> Bool {
            lhs.id == rhs.id
        }
        public let id: String
        public let sentence: BibleVerse
        public var sentenceState: VerseTextFeature.State
        public var canvasState: CanvasFeature.State
        public var drewHistoryState: VerseDrawingHistoryFeature.State
        public var isPresentDrewHistory: Bool = false
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false

        public init(sentence: BibleVerse, drawing: BibleDrawing?) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.verse)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       sentence: sentence.sentenceScript)
            self.canvasState = .init(sentence: sentence, drawing: drawing)
            self.drewHistoryState = .init(title: sentence.title, verse: sentence.verse)
        }
        
        public static var initialState = Self(sentence: BibleVerse.initialState,
                                               drawing: BibleDrawing.init(
                                                bibleTitle: BibleChapter(title: .leviticus, chapter: 4), verse: 1))
    }
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            case setBible
            case setHeight(height: CGFloat)
            case presentDrewHistory(Bool)
        }
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(VerseTextFeature.Action)
        case canvasAction(CanvasFeature.Action)
        case drewHistoryAction(VerseDrawingHistoryFeature.Action)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \.scope.sentenceAction) {
            VerseTextFeature()
        }
        Scope(state: \.canvasState,
              action: \.scope.canvasAction) {
            CanvasFeature()
        }
        Scope(state: \.drewHistoryState,
              action: \.scope.drewHistoryAction) {
            VerseDrawingHistoryFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.presentDrewHistory(let isPresent)):
                state.isPresentDrewHistory = isPresent
            case .scope(.drewHistoryAction(.setPresentDrawing(let drawing))):
                state.isPresentDrewHistory = false
                return .run { send in
                    await send(.scope(.canvasAction(.setDrawing(drawing))))
                }
            default: break
                
            }
            return .none
        }
    }
    
}
