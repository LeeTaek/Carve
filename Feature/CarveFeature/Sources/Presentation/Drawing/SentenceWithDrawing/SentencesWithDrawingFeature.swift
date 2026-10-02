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
                                       verseEnd: sentence.verseEnd,
                                       sentence: sentence.sentenceScript)
            self.canvasState = .init(sentence: sentence, drawing: drawing)
            self.drewHistoryState = .init(title: sentence.title, verse: sentence.verse)
        }
        
        /// @Model(`BibleDrawing`)을 담아 Sendable 이 아니므로 저장 프로퍼티 대신 계산 프로퍼티다(N-Canvas).
        public static var initialState: Self {
            Self(sentence: BibleVerse.initialState,
                 drawing: BibleDrawing.init(
                    bibleTitle: BibleChapter(title: .leviticus, chapter: 4), verse: 1))
        }
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
            case .scope(.drewHistoryAction(.setPresentDrawing(let snapshot))):
                state.isPresentDrewHistory = false
                // 액션만 전달하는 자리라 .run 을 쓸 이유가 없다. 고른 회차(DTO)를 캔버스가 행 모양으로 옮긴다.
                return .send(.scope(.canvasAction(.setDrawing(snapshot))))
            default: break
                
            }
            return .none
        }
    }
    
}
