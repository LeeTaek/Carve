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
    public struct State: Equatable, Identifiable {
        public var id: String
        public var drawing: DrawingVO
        public var lineColor: UIColor
        public var lineWidth: CGFloat
        public init(drawing: DrawingVO,
                    lineColor: UIColor,
                    lineWidth: CGFloat) {
            self.id = "drawingData.\(drawing.id)"
            self.drawing = drawing
            self.lineColor = lineColor
            self.lineWidth = lineWidth
        }

        public static let initialState = Self(drawing: .init(bibleTitle: .initialState,
                                                             section: 1),
                                              lineColor: .black,
                                              lineWidth: 4)
    }
    
    @Dependency(\.drawingData) var drawingContext

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveDrawing(PKDrawing)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .saveDrawing(let newDrawing):
                var drawing = state.drawing
                drawing.lineData = newDrawing.dataRepresentation()
                return .run { [drawing] _ in
                    try await drawingContext.update(item: drawing)
                }

            default:
                break
            }
            return .none
        }
    }

}
