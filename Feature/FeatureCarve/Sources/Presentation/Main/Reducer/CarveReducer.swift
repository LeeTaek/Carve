//
//  CarveReducer.swift
//  Feature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import CommonUI
import DomainRealm
import Foundation
import Resources

import ComposableArchitecture

@Reducer
public struct CarveReducer {
    public init() { }
    public struct State: Equatable {
        public init() { }
        public let id: UUID = UUID()
        public var isScrollDown: Bool = false
        public var sentences: [SentenceVO] = []
        public var titleState = TitleReducer.State.initialState
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
        static let initialState = Self()
    }
    
    public enum Action: FeatureAction, CommonUI.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    public enum ViewAction: Equatable {
        case onAppear
        case isScrollDown(Bool)
        case moveNextChapter
        case moveBeforeChapter
    }
    
    public enum InnerAction: Equatable {
        
    }
    
    @CasePathable
    public enum ScopeAction {
        case titleAction(TitleReducer.Action)
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingReducer>)
    }

    public var body: some Reducer<State, Action> {
        Scope(state: \.titleState,
              action: \Action.Cases.scope.titleAction) {
            TitleReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                let currentChapter = state.titleState.currentBible
                let sentences = fetchBible(chapter: currentChapter)
                sentences.forEach {
                    let currentState = SentencesWithDrawingReducer.State(sentence: $0)
                    state.sentenceWithDrawingState.append(currentState)
                }
                
            case .view(.isScrollDown(let isScrollDown)):
                state.isScrollDown = isScrollDown
                
            case .view(.moveNextChapter):
                break

            case .view(.moveBeforeChapter):
                break
                
            case .scope(.titleAction(.inner(.selectDidFinish))):
                let currentChapter = state.titleState.currentBible
                let sentences = fetchBible(chapter: currentChapter)
                Log.debug(sentences)
            default:
                break
            }
            return .none
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \Action.Cases.scope.sentenceWithDrawingAction) {
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
                return SentenceVO.init(title: chapter.title.rawValue,
                                       chapter: chapter.chapter,
                                       sentence: sentence)
            }
        } catch let error {
            Log.error(error.localizedDescription)
        }
        
        return sentences
    }
    
}
