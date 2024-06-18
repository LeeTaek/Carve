//
//  PencilPalatteReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct PencilPalatteReducer {
    @ObservableState
    public struct State {
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.appStorage("selectedColorIndex")) public var selectedColorIndex: Int = 0
        @Shared(.appStorage("selectedWidthIndex")) public var selectedWidthIndex: Int = 0
        public var palatteColors: [UIColor]
        public var palattePencilType: PKInkingTool.InkType
        public var lineWidths: [CGFloat]
        public var popoverPoint: CGPoint = .zero
        @Presents var navigation: Destination.State?
        public static var initialState = State(palatteColors: [.black, .blue, .red],
                                               palattePencilType: .pen,
                                               lineWidths: [2.0, 4.0, 6.0]
        )
    }

    public enum Action {
        case setConfigPencilColor(UIColor)
        case setConfigPencilType(PKInkingTool.InkType)
        case changePencilColor(index: Int, color: UIColor)
        case setColor(Int)
        case setPencilType(PKInkingTool.InkType)
        case setLineWidth(Int)
        case popoverLineWidth
        case popoverColor
        case setPopoverPoint(CGPoint)
        case navigation(PresentationAction<Destination.Action>)
    }
    
    @Reducer
    public enum Destination {
        case lineWidthPalatte(LineWidthPalatteReducer)
        case colorPalatte(ColorPalatteReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setConfigPencilColor(let color):
                state.pencilConfig.lineColor = CodableColor(color: color)
            case .setConfigPencilType(let type):
                state.pencilConfig.pencilType = type
            case let .changePencilColor(index, color):
                state.palatteColors[index] = color
            case .setColor(let index):
                state.selectedColorIndex = index
                withAnimation {
                    state.pencilConfig.lineColor = CodableColor(color: state.palatteColors[index])
                }
            case .setPencilType(let type):
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.pencilConfig.pencilType = type
                }
            case .setLineWidth(let index):
                state.selectedWidthIndex = index
                state.pencilConfig.lineWidth = state.lineWidths[index]
            case .setPopoverPoint(let point):
                state.popoverPoint = point
            case .popoverColor:
                state.navigation = .colorPalatte(.initialState)
            case .popoverLineWidth:
                state.navigation = .lineWidthPalatte(.initialState)
            default: break
            }
            return .none
        }
        .ifLet(\.$navigation, action: \.navigation)
    }
}
