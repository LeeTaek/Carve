//
//  CarveReducer.swift
//  Feature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import Resources
import SwiftUI
import SwiftData

import ComposableArchitecture

@Reducer
public struct CarveReducer {
    public init() { }
    @ObservableState
    public struct State {
        public var lastChapter: Int
        public var columnVisibility: NavigationSplitViewVisibility
        public var carveDetailState: CarveDetailReducer.State
        @Shared(.appStorage("title")) public var currentTitle: TitleVO = .initialState
        public var selectedTitle: BibleTitle?
        public var selectedChapter: Int?
        public var showOldTestmentSection: Bool = true
        public var showNewTestmentSection: Bool = true
        
        public static let initialState = State(
            lastChapter: 1,
            columnVisibility: .detailOnly,
            carveDetailState: .initialState
        )
    }
    
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: FeatureAction, Core.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    @CasePathable
    public enum ViewAction: Equatable {
        case moveToSetting
        case toggleShowOldTestmentSection(Bool)
        case toggleShowNewTestmentSection(Bool)
    }
    
    public enum InnerAction: Equatable {
    }
    
    @CasePathable
    public enum ScopeAction {
        case carveDetailAction(CarveDetailReducer.Action)
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.selectedTitle) { _, newValue in
                Reduce { state, _ in
                    guard let title = newValue else { return .none }
                    if state.currentTitle.title != title {
                        state.selectedChapter = nil
                    }
                    state.currentTitle.title = title
                    return .none
                }
            }
            .onChange(of: \.selectedChapter) { _, newValue in
                Reduce { state, _ in
                    guard let selectedChapter = newValue else { return .none }
                    state.currentTitle.chapter = selectedChapter
                    state.columnVisibility = .detailOnly
                    return .run { send in
                        await send(.scope(.carveDetailAction(.inner(.fetchSentence))))
                    }
                }
            }
        Scope(state: \.carveDetailState,
              action: \.scope.carveDetailAction) {
            CarveDetailReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .scope(.carveDetailAction(.scope(.headerAction(.titleDidTapped)))):
                state.selectedTitle = state.currentTitle.title
                state.selectedChapter = state.currentTitle.chapter
                state.columnVisibility = .all
            case .view(.moveToSetting):
                Log.debug("move To settings")
            case .view(.toggleShowOldTestmentSection(let isShow)):
                    state.showOldTestmentSection = isShow
            case .view(.toggleShowNewTestmentSection(let isShow)):
                    state.showNewTestmentSection = isShow
            default: break
            }
            return .none
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
