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
        public var drawing: DrawingVO
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        public init(drawing: DrawingVO) {
            self.id = "drawingData.\(drawing.id)"
            self.drawing = drawing
        }
        public static let initialState = Self(drawing: .init(bibleTitle: .initialState,
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
                let drawing = state.drawing
                drawing.lineData = newDrawing.dataRepresentation()
                return .run { _ in
                    try await drawingContext.update(item: drawing)
                }
            case .registUndoCanvas(let canvas):
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
