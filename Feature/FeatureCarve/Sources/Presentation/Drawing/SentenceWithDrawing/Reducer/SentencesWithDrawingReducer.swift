//
//  SentencesWithDrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import CommonUI
import DomainRealm
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentencesWithDrawingReducer {
    public struct State: Equatable, Identifiable {
        public let id: String
        public let sentence: SentenceVO
        public var sentenceState: BibleSentenceReducer.State
        public var drawingState: DrawingReducer.State
        
        public init(sentence: SentenceVO) {
            self.id = "\(sentence.title).\(sentence.chapter).\(sentence.section)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       section: sentence.section,
                                       sentence: sentence.sentenceScript)
            self.drawingState = .init(title: .init(title: .getTitle(sentence.title),
                                                   chapter: sentence.chapter),
                                      section: sentence.chapter)
        }
    }
    
    
    public enum Action: FeatureAction, CommonUI.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    
    public enum ViewAction {
        case setHeight(height: CGFloat)
        case calculateLineOffsets(Int, CGFloat)
    }
    
    public enum InnerAction { }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(BibleSentenceReducer.Action)
        case drawingAction(DrawingReducer.Action)
    }
    
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \Action.Cases.scope.sentenceAction) {
            BibleSentenceReducer()
        }
        Scope(state: \.drawingState,
              action: \Action.Cases.scope.drawingAction) {
            DrawingReducer()
                ._printChanges()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.calculateLineOffsets(let lineCount, let frameHeight)):
                let offsetY = calcurateLineOffsets(state: state.sentenceState,
                                                   lineCount: lineCount,
                                                   height: frameHeight)
                return .send(.scope(.drawingAction(.view(.setUnderlineOffset(offset: offsetY)))))

            default:
                return .none
            }
        }
    }
    
    private func calcurateLineOffsets(state: BibleSentenceReducer.State,
                                      lineCount: Int,
                                      height: CGFloat) -> [CGFloat] {
        let fontHeight = state.font.font(size: state.fontSize).lineHeight
        let paddingSpace = (state.lineSpace - fontHeight) / 2
        var offsets: [CGFloat] = []

        for _ in 1...lineCount {
            offsets.append(paddingSpace + fontHeight)
        }
        
        return offsets
    }
}
