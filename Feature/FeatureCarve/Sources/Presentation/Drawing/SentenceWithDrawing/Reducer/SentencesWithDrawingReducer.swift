//
//  SentencesWithDrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CommonUI
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentencesWithDrawingReducer {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public let id: String
        public let sentence: SentenceVO
        public var sentenceState: BibleSentenceReducer.State
        public var canvasState: CanvasReducer.State
        public var underLineCount: Int = 1
        public var underlineOffset: [CGFloat] = [.zero]
        
        public init(sentence: SentenceVO) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.section)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       section: sentence.section,
                                       sentence: sentence.sentenceScript)
            self.canvasState = .init(drawing: .init(bibleTitle: sentence.title,
                                                    section: sentence.section),
                                     lineColor: .black,
                                     lineWidth: 4)
        }
    }
    
    
    public enum Action: FeatureAction, CommonUI.ScopeAction, CommonUI.AsyncAction {
        case view(ViewAction)
        case inner(InnerAction)
        case async(AsyncAction)
        case scope(ScopeAction)
    }
    
    public enum ViewAction {
        case setBible
        case setHeight(height: CGFloat)
        case calculateLineOffsets(CGRect)
    }
    
    public enum InnerAction { }
    
    public enum AsyncAction: Equatable {
        case setSubscription
        case clearSubscription
        case updateSubscription
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(BibleSentenceReducer.Action)
        case canvasAction(CanvasReducer.Action)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \Action.Cases.scope.sentenceAction) {
            BibleSentenceReducer()
        }
        Scope(state: \.canvasState,
              action: \Action.Cases.scope.canvasAction) {
            CanvasReducer()
                ._printChanges()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.calculateLineOffsets(let rect)):
                let offsetY = calcurateLineOffsets(state: state.sentenceState,
                                                   rect: rect)
                state.underlineOffset = offsetY
                state.underLineCount = offsetY.count
                return .none
            default:
                return .none
            }
        }
    }
    
    
    private func calcurateLineOffsets(state: BibleSentenceReducer.State,
                                      rect: CGRect) -> [CGFloat] {
        let frameHeight = rect.height
        let lineCount = Int(frameHeight / state.lineSpace)
        let fontHeight = state.font.font(size: state.fontSize).lineHeight
        let paddingSpace = (state.lineSpace - fontHeight) / 2
        var offsets: [CGFloat] = []
        for _ in 1...lineCount {
            offsets.append(paddingSpace + fontHeight)
        }
        return offsets
    }
}
