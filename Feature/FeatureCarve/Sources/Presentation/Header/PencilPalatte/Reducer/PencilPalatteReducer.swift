//
//  PencilPalatteReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
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
        @Shared(.appStorage("palatteColorSet")) public var palatteColors: [CodableColor] = [.init(color: .black),
                                                                                            .init(color: .blue),
                                                                                            .init(color: .red)]
        @Shared(.appStorage("lineWidthSet")) public var lineWidths: [CGFloat] = [2.0, 4.0, 6.0]
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        public var palattePencilType: PKInkingTool.InkType
        public var popoverPoint: CGPoint = .zero
        @Presents var navigation: Destination.State?
                
        public static var initialState = State(palattePencilType: .pen)
    }

    @Dependency(\.undoManager) private var undoManager
    
    public enum Action {
        case setConfigPencilColor(UIColor)
        case setConfigPencilType(PKInkingTool.InkType)
        case changePencilColor(index: Int, color: UIColor)
        case setColor(Int)
        case setPencilType(PKInkingTool.InkType)
        case setLineWidth(Int)
        case popoverLineWidth(Int)
        case popoverColor(Int)
        case setPopoverPoint(CGPoint)
        case navigation(PresentationAction<Destination.Action>)
        case undo
        case redo
        case setCanUndo
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
                state.$pencilConfig.withLock { $0.lineColor = CodableColor(color: color) }
            case .setConfigPencilType(let type):
                state.$pencilConfig.withLock { $0.pencilType = type }
            case let .changePencilColor(index, color):
                state.$palatteColors.withLock { $0[index] = .init(color: color) }
            case .setColor(let index):
                withAnimation {
                    state.$selectedColorIndex.withLock { $0 = index }
                    state.$pencilConfig.withLock { $0.lineColor = state.palatteColors[index] }
                }
            case .setPencilType(let type):
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.$pencilConfig.withLock { $0.pencilType = type }
                }
            case .setLineWidth(let index):
                state.$selectedWidthIndex.withLock { $0 = index }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[index] }
            case .setPopoverPoint(let point):
                state.popoverPoint = point
            case .popoverColor(let index):
                state.navigation = .colorPalatte(.init(index: index, color: state.palatteColors[index]))
            case .popoverLineWidth(let index):
                state.navigation = .lineWidthPalatte(.init(lineWidth: state.lineWidths[index], index: index))
            case .navigation(.dismiss):
                state.$pencilConfig.withLock { $0.lineColor = state.palatteColors[state.selectedColorIndex] }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[state.selectedWidthIndex] }
            case .undo:
                undoManager.undo()
                return .run { send in
                    await send(.setCanUndo)
                }
            case .redo:
                undoManager.redo()
                return .run { send in
                    await send(.setCanUndo)
                }
            case .setCanUndo:
                state.$canUndo.withLock { $0 = undoManager.canUndo }
                state.$canRedo.withLock { $0 = undoManager.canRedo }

            default: break
            }
            return .none
        }
        .ifLet(\.$navigation, action: \.navigation)
    }
}
