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
    
    public enum Action: FeatureAction, Core.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case scope(ScopeAction)
    }
    @CasePathable
    public enum ViewAction {
        case headerAnimation(CGFloat, CGFloat)
        case scrollToTop
        case setProxy(ScrollViewProxy, ObjectIdentifier)
    }
    public enum InnerAction {
        case fetchSentence
        case setSentence([BibleVerse], [DrawingVO])
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
            case .inner(.fetchSentence):
                let title = state.headerState.currentTitle
                return .run { send in
                    let sentences = try fetchBible(chapter: title)
                    do {
                        let storedDrawing = try await drawingContext.fetch(chapter: title)
                        await send(.inner(.setSentence(sentences, storedDrawing)))
                    } catch {
                        Log.debug("fetch drawing error", error)
                        await send(.inner(.setSentence([], [])))
                    }
                }
            case .inner(.setSentence(let sentences, let drawings)):
                state.sentenceWithDrawingState.removeAll()
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingReducer.State> = []
                let verseSet = Set(drawings.compactMap { $0.section })
                for sentence in sentences {
                    if verseSet.contains(sentence.verse) {
                        let drawing = drawings.filter { $0.section == sentence.verse }.first
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
                guard case let .saveDrawing(drawing) = action,
                      let index = state.sentenceWithDrawingState.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                let sentenceState = state.sentenceWithDrawingState[index]
                return .run { _ in
                    do {
                        guard let drawing = sentenceState.canvasState.drawing else { return }
                        try await drawingContext.updateDrawing(drawing: drawing)
                    } catch {
                        Log.debug("drawingError", error)
                    }
                    
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
    
    
    func fetchBible(chapter: BibleChapter) throws(CarveReducerError) -> [BibleVerse] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [BibleVerse] = []
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
                    return BibleVerse.init(title: chapter, sentence: sentence)
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
