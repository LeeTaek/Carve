//
//  CarveDetailReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import Resources
import SwiftUI

import ComposableArchitecture

@Reducer
public struct CarveDetailReducer {
    @ObservableState
    public struct State {
        public var headerState: HeaderReducer.State
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
        public var proxy: ScrollViewProxy?
        public var firstItemID: ObjectIdentifier?
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) var undoManager
    
    public enum Action: ViewAction, Core.ScopeAction {
        case view(View)
        case inner(InnerAction)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            case fetchSentence
            case headerAnimation(CGFloat, CGFloat)
            case scrollToTop
            case setProxy(ScrollViewProxy, ObjectIdentifier)
        }
    }

    public enum InnerAction {
        case setSentence([SentenceVO], [BibleDrawing])
    }
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingReducer>)
        case headerAction(HeaderReducer.Action)
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                return .run { send in
                    await send(.scope(.headerAction(.headerAnimation(previous, current))))
                }
            case .view(.fetchSentence):
                let title = state.headerState.currentTitle
                return .run { send in
                    let sentences = try fetchBible(chapter: title)
                    do {
                        let storedDrawing = try await drawingContext.fetch(title: title)
                        await send(.inner(.setSentence(sentences, storedDrawing)))
                        Log.debug("fetched Draiwng Count", storedDrawing.count)
                    } catch {
                        Log.error("fetch drawing error", error)
                        await send(.inner(.setSentence([], [])))
                    }
                }
            case .inner(.setSentence(let sentences, let drawings)):
                state.sentenceWithDrawingState.removeAll()
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
                let sectionSet = Set(drawings.compactMap { $0.verse })
                for sentence in sentences {
                    if sectionSet.contains(sentence.verse) {
                        let candidates = drawings.filter { $0.verse == sentence.verse }
                        let drawing = candidates.first(where: { $0.isPresent == true })
                        ?? candidates.sorted(by: { ($0.updateDate ?? .distantPast) > ($1.updateDate ?? .distantPast) }).first
                        sentenceState.append(SentencesWithDrawingReducer.State(sentence: sentence,
                                                                               drawing: drawing))
                    } else {
                        sentenceState.append(SentencesWithDrawingReducer.State(sentence: sentence,
                                                                               drawing: nil))
                    }
                }
                state.sentenceWithDrawingState = sentenceState
                undoManager.clear()
                return .run { send in
                    await send(.view(.scrollToTop))
                }
            case .view(.setProxy(let proxy, let id)):
                state.proxy = proxy
                state.firstItemID = id
            case .view(.scrollToTop):
                guard let id = state.firstItemID else { return .none }
                let anchorPoint = state.headerState.headerHeight / UIScreen.main.bounds.height
                withAnimation(.easeInOut(duration: 0.5)) {
                    state.proxy?.scrollTo(id, anchor: UnitPoint(x: 0, y: anchorPoint))
                }
            case .scope(.sentenceWithDrawingAction(.element(id: let id,
                                                            action: .scope(.canvasAction(let action))))):
                guard case .saveDrawing = action,
                      let index = state.sentenceWithDrawingState.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                let sentenceState = state.sentenceWithDrawingState[index]
                return .run { _ in
                    guard let drawing = sentenceState.canvasState.drawing else { return }
                    try await drawingContext.updateDrawing(drawing: drawing)
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
    
    
    func fetchBible(chapter: TitleVO) throws(CarveReducerError) -> [SentenceVO] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [SentenceVO] = []
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else { return sentences}
        do {
            let bible = try String(contentsOfFile: textPath,
                                   encoding: String.Encoding(rawValue: encodingEUCKR))
            sentences = try bible.components(separatedBy: "\r")
                .filter {
                    guard let num = $0.components(separatedBy: ":").first,
                          let first = Int(num) else { throw CarveReducerError.chapterConvertError }
                    return first == chapter.chapter
                }
                .map { sentence in
                    return SentenceVO.init(title: chapter, sentence: sentence)
                }
        } catch {
            throw .fetchSentenceError
        }
        return sentences
    }
    
    
    enum CarveReducerError: Error {
        case fetchSentenceError
        case chapterConvertError
    }
}
