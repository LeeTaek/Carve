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
    
    @Dependency(\.undoManager) private var undoManager

    public enum Action {
        case saveDrawing(PKDrawing)
        case registUndoCanvas(PKCanvasView)
        case setDrawing(DrawingVO)
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .saveDrawing(let newDrawing):
                if let drawing = state.drawing {
                    drawing.lineData = newDrawing.dataRepresentation()
                    drawing.updateDate = Date.now
                } else {
                    state.drawing = DrawingVO(bibleTitle: state.title,
                                              section: state.section,
                                              lineData: newDrawing.dataRepresentation())
                }
            case .registUndoCanvas(let canvas):
                if undoManager.isPerformingUndoRedo {
                    undoManager.isPerformingUndoRedo = false
                    return .none
                }
                undoManager.registerUndoAction(for: canvas)
                state.$canUndo.withLock { $0 = undoManager.canUndo }
                state.$canRedo.withLock { $0 = undoManager.canRedo }
            case .setDrawing(let drawing):
                state.drawing = drawing
            }
            return .none
        }
    }

}
