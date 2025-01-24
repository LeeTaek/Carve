//
//  SentencesWithDrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentencesWithDrawingReducer {
    @ObservableState
    public struct State: Identifiable, Equatable {
        public static func == (lhs: SentencesWithDrawingReducer.State, rhs: SentencesWithDrawingReducer.State) -> Bool {
            lhs.id == rhs.id
        }
        public let id: String
        public let sentence: BibleVerse
        public var sentenceState: SentenceReducer.State
        public var canvasState: CanvasReducer.State
        public var underLineCount: Int = 1
        public var underlineOffset: [CGFloat] = [.zero]
        
        public init(sentence: BibleVerse, drawing: BibleDrawing?) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.verse)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       sentence: sentence.sentenceScript)
            self.canvasState = .init(sentence: sentence, drawing: drawing)
        }
    }
    
    public enum Action: FeatureAction, Core.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    
    public enum ViewAction {
        case setBible
        case setHeight(height: CGFloat)
        case calculateLineOffsets(CGRect)
    }
    
    public enum InnerAction { }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(SentenceReducer.Action)
        case canvasAction(CanvasReducer.Action)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \.scope.sentenceAction) {
            SentenceReducer()
        }
        Scope(state: \.canvasState,
              action: \.scope.canvasAction) {
            CanvasReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.calculateLineOffsets(let rect)):
                let offsetY = calcurateLineOffsets(state: state.sentenceState,
                                                   rect: rect)
                state.underlineOffset = offsetY
                state.underLineCount = offsetY.count
                return .none
            case .scope(.sentenceAction(.inner(.redrawUnderline(let rect)))):
                return .run { send in
                    await send(.view(.calculateLineOffsets(rect)))
                }
                
            default:
                return .none
            }
        }
    }
    
    
    private func calcurateLineOffsets(state: SentenceReducer.State,
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
