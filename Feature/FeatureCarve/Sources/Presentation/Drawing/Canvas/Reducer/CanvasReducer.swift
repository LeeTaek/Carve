//
//  CanvasReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import PencilKit
import UIKit

import ComposableArchitecture

@Reducer
public struct CanvasReducer {
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var drawing: DrawingVO?
        public var title: TitleVO
        public var section: Int
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        public init(sentence: SentenceVO, drawing: DrawingVO?) {
            self.id = "drawingData.\(sentence.sentenceScript)"
            self.drawing = drawing
            self.title = sentence.title
            self.section = sentence.section
        }
        public static let initialState = Self(sentence: .initialState,
                                              drawing: .init(bibleTitle: .initialState,
                                                             section: 1))
    }
    
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) private var undoManager

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveDrawing(PKDrawing)
        case registUndoCanvas(PKCanvasView)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .saveDrawing(let newDrawing):
                if let drawing = state.drawing {
                    drawing.lineData = newDrawing.dataRepresentation()
                } else {
                    state.drawing = DrawingVO(bibleTitle: state.title,
                                              section: state.section,
                                              lineData: newDrawing.dataRepresentation())
                }
                return .run { [drawing = state.drawing] _ in
                    do {
                        guard let drawing else { return }
                        try await drawingContext.updateDrawing(drawing: drawing)
                    } catch {
                        Log.debug("drawing error: \(error)")
                    }
                }
            case .registUndoCanvas(let canvas):
                if undoManager.isPerformingUndoRedo {
                    undoManager.isPerformingUndoRedo = false
                    return .none
                }
                undoManager.registerUndoAction(for: canvas)
                state.canUndo = undoManager.canUndo
                state.canRedo = undoManager.canRedo
            default:
                break
            }
            return .none
        }
    }

}
