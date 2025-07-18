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
        public let sentence: SentenceVO
        public var sentenceState: SentenceFeature.State
        public var canvasState: CanvasFeature.State
        public var drewHistoryState: SentenceDrewHistoryListFeature.State
        public var underLineCount: Int = 1
        public var underlineOffset: [CGFloat] = [.zero]
        public var isPresentDrewHistory: Bool = false
        
        public init(sentence: SentenceVO, drawing: BibleDrawing?) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.verse)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       sentence: sentence.sentenceScript)
            self.canvasState = .init(sentence: sentence, drawing: drawing)
            self.drewHistoryState = .init(title: sentence.title, verse: sentence.verse)
        }
    }
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            case setBible
            case setHeight(height: CGFloat)
            case calculateLineOffsets(CGRect)
            case presentDrewHistory(Bool)
        }
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(SentenceFeature.Action)
        case canvasAction(CanvasFeature.Action)
        case drewHistoryAction(SentenceDrewHistoryListFeature.Action)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \.scope.sentenceAction) {
            SentenceFeature()
        }
        Scope(state: \.canvasState,
              action: \.scope.canvasAction) {
            CanvasFeature()
        }
        Scope(state: \.drewHistoryState,
              action: \.scope.drewHistoryAction) {
            SentenceDrewHistoryListFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.calculateLineOffsets(let rect)):
                let offsetY = calcurateLineOffsets(state: state.sentenceState,
                                                   rect: rect)
                state.underlineOffset = offsetY
                state.underLineCount = offsetY.count
            case .scope(.sentenceAction(.view(.redrawUnderline(let rect)))):
                return .run { send in
                    await send(.view(.calculateLineOffsets(rect)))
                }
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
    
    
    private func calcurateLineOffsets(state: SentenceFeature.State,
                                      rect: CGRect) -> [CGFloat] {
        let frameHeight = rect.height
        let lineCount = Int(frameHeight / state.sentenceSetting.lineSpace)
        let fontHeight = state.sentenceSetting.fontFamily.font(size: state.sentenceSetting.fontSize).lineHeight
        let paddingSpace = (state.sentenceSetting.lineSpace - fontHeight) / 2
        var offsets: [CGFloat] = []
        guard lineCount > 0 else { return offsets }
        for _ in 1...lineCount {
            offsets.append(paddingSpace + fontHeight)
        }
        return offsets
    }
}
