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
import SwiftUI

import ComposableArchitecture

@Reducer
public struct CarveReducer {
    public init() { }
    @ObservableState
    public struct State: Equatable {
        public var isScrollDown: Bool
        public var sentences: [SentenceVO]
        public var currentTitle: TitleVO
        public var lastChapter: Int
        public var isTitlePresent: Bool
        public var columnVisibility: NavigationSplitViewVisibility
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
        public static let initialState = State(
            isScrollDown: false,
            sentences: [],
            currentTitle: .initialState,
            lastChapter: 1,
            isTitlePresent: false,
            columnVisibility: .detailOnly
        )
    }
    
    public enum Action: FeatureAction, CommonUI.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    public enum ViewAction: Equatable {
        case onAppear
        case isScrollDown(Bool)
        case moveNextChapter
        case moveBeforeChapter
        case isPresentTitle(Bool)
        case titleDidTapped
    }
    
    public enum InnerAction: Equatable {
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingReducer>)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                let currentChapter = state.currentTitle
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
                
            case let .view(.isPresentTitle(isPresent)):
                state.isTitlePresent = isPresent
                
            case .view(.titleDidTapped):
                state.columnVisibility = .all
                
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
