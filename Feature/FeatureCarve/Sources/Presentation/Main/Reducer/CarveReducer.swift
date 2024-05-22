//
//  CarveReducer.swift
//  Feature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import CommonUI
import Domain
import Resources
import SwiftUI
import SwiftData

import ComposableArchitecture

@Reducer
public struct CarveReducer {
    public init() { }
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage("title")) public var currentTitle: TitleVO = .initialState
        public var viewProperty: ViewProperty
        public var lastChapter: Int
        public var columnVisibility: NavigationSplitViewVisibility
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
        public static let initialState = State(
            viewProperty: ViewProperty(),
            lastChapter: 1,
            columnVisibility: .detailOnly
        )
        
        public struct ViewProperty: Equatable {
            public var headerHeight: CGFloat = 0
            public var headerOffset: CGFloat = 0
            public var lastHeaderOffset: CGFloat = 0
            public var direction: SwipeDirection = .none
            public var shiftOffset: CGFloat = 0
            public var selectedTitle: BibleTitle?
            public var selectedChapter: Int?
            
            public enum SwipeDirection {
                case up
                case down
                case none
            }
        }
    }
    
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: FeatureAction, CommonUI.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    public enum ViewAction: Equatable {
        case headerAnimation(CGFloat, CGFloat)
        case setHeaderHeight(CGFloat)
        case moveNextChapter
        case moveBeforeChapter
        case isPresentTitle(Bool)
        case titleDidTapped
        case moveToSetting
    }
    
    public enum InnerAction: Equatable {
        case fetchSentence
        case setSentence([SentenceVO], [DrawingVO])
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingReducer>)
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.viewProperty.selectedTitle) { _, _ in
                Reduce { state, _ in
                    state.columnVisibility = .doubleColumn
                    return .none
                }
            }
            .onChange(of: \.viewProperty.selectedChapter) { _, newValue in
                Reduce { state, _ in
                    guard let selectedTitle = state.viewProperty.selectedTitle,
                          let selectedChapter = newValue else { return .none }
                    state.currentTitle = TitleVO(title: selectedTitle, chapter: selectedChapter)
                    state.columnVisibility = .detailOnly
                    return .run { send in
                        await send(.inner(.fetchSentence))
                    }
                }
            }
        
        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                if previous > current {
                    if state.viewProperty.direction != .up  && current < 0 {
                        state.viewProperty.shiftOffset = current - state.viewProperty.headerOffset
                        state.viewProperty.direction = .up
                        state.viewProperty.lastHeaderOffset = state.viewProperty.headerHeight
                    }
                    let offset = current < 0 ? (current - state.viewProperty.shiftOffset) : 0
                    state.viewProperty.headerOffset = (-offset < state.viewProperty.headerHeight
                                                        ? (offset < 0 ? offset : 0)
                                                        : -state.viewProperty.headerHeight)
                } else {
                    if state.viewProperty.direction != .down {
                        state.viewProperty.shiftOffset = current
                        state.viewProperty.direction = .down
                        state.viewProperty.lastHeaderOffset = state.viewProperty.headerOffset
                    }
                    let offset = state.viewProperty.lastHeaderOffset + (current - state.viewProperty.shiftOffset)
                    state.viewProperty.headerOffset = (offset > 0 ? 0 : offset)
                }
                
            case .view(.setHeaderHeight(let height)):
                state.viewProperty.headerHeight = height
                
            case .view(.moveNextChapter):
                break
                
            case .view(.moveBeforeChapter):
                break
                
            case .view(.titleDidTapped):
                state.columnVisibility = .all
                
            case .view(.moveToSetting):
                Log.debug("move To settings")
                
            case .inner(.fetchSentence):
                let title = state.currentTitle
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
            default: break
            }
            return .none
        }
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
