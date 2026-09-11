//
//  PencilPalatteReducer.swift
//  PencilPalatteFeature
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct PencilPalatteFeature {
    @ObservableState
    public struct State {
        public var popoverPoint: CGPoint = .zero
        
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.appStorage("selectedColorIndex")) public var selectedColorIndex: Int = 0
        @Shared(.appStorage("selectedWidthIndex")) public var selectedWidthIndex: Int = 0
        @Shared(.appStorage("palatteColorSet")) public var palatteColors: [CodableColor] = [
            .init(color: .black),
            .init(color: .blue),
            .init(color: .red)
        ]
        @Shared(.appStorage("lineWidthSet")) public var lineWidths: [CGFloat] = [2.0, 4.0, 6.0]
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        /// undo/redo 를 팔레트가 아니라 캔버스(단일 Canvas, `ChapterCanvasFeature`)가 처리한다.
        ///
        /// true 면 `SharedUndoManager` 를 건드리지 않고 공유 `canUndo`/`canRedo` 도 덮어쓰지 않는다 —
        /// 단일 Canvas 는 자기 undoManager 상태를 같은 키에 써 두는데, 팔레트가 비어 있는 `SharedUndoManager` 값(false)으로
        /// 덮으면 undo 직후 버튼이 꺼진다. 값은 `CarveDetailFeature` 가 장 진입 때 정한다.
        public var delegatesUndoToCanvas: Bool = false
        /// 마지막으로 고른 잉크(연필 · 펜 · 형광펜). 팔레트의 펜 칸 하나가 세 잉크를 대표하므로(시안 M2),
        /// 지우개에서 펜 칸을 누르면 이 잉크로 돌아간다.
        public var lastInkType: PKInkingTool.InkType = .pen

        @Presents var navigation: Destination.State?
                
        public static var initialState = State()
    }
    @Dependency(\.undoManager) private var undoManager

    
    public enum Action: ViewAction {
        case setConfigPencilColor(UIColor)
        case setConfigPencilType(PKInkingTool.InkType)
        case changePencilColor(index: Int, color: UIColor)
        case navigation(PresentationAction<Destination.Action>)
        case setCanUndo

        case view(View)
        
        public enum View {
            case setColor(Int)
            case setPopoverPoint(CGPoint)
            case setLineWidth(Int)
            case setPencilType(PKInkingTool.InkType)
            case undo
            case redo
            case popoverColor(Int)
            case popoverLineWidth(Int)
        }
    }
    
    @Reducer
    public enum Destination {
        case lineWidthPalatte(LineWidthPalatteFeature)
        case colorPalatte(ColorPalatteFeature)
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
            case .view(.setColor(let index)):
                withAnimation {
                    state.$selectedColorIndex.withLock { $0 = index }
                    state.$pencilConfig.withLock { $0.lineColor = state.palatteColors[index] }
                }
            case .view(.setPencilType(let type)):
                if type != .monoline {
                    state.lastInkType = type
                }
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.$pencilConfig.withLock { $0.pencilType = type }
                }
            case .view(.setLineWidth(let index)):
                state.$selectedWidthIndex.withLock { $0 = index }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[index] }
            case .view(.setPopoverPoint(let point)):
                state.popoverPoint = point
            case .view(.popoverColor(let index)):
                state.navigation = .colorPalatte(.init(index: index, color: state.palatteColors[index]))
            case .view(.popoverLineWidth(let index)):
                state.navigation = .lineWidthPalatte(.init(lineWidth: state.lineWidths[index], index: index))
            case .navigation(.dismiss):
                state.$pencilConfig.withLock { $0.lineColor = state.palatteColors[state.selectedColorIndex] }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[state.selectedWidthIndex] }
            case .view(.undo):
                // 단일 Canvas 경로에서는 부모(CarveDetailFeature)가 이 액션을 캔버스의 undoTapped 로 옮긴다.
                guard !state.delegatesUndoToCanvas else { return .none }
                undoManager.undo()
                return .run { send in
                    await send(.setCanUndo)
                }
            case .view(.redo):
                guard !state.delegatesUndoToCanvas else { return .none }
                undoManager.redo()
                return .run { send in
                    await send(.setCanUndo)
                }
            case .setCanUndo:
                // 캔버스가 처리할 때는 공유 값의 주인이 캔버스다 — SharedUndoManager 값으로 덮지 않는다.
                guard !state.delegatesUndoToCanvas else { return .none }
                state.$canUndo.withLock { $0 = undoManager.canUndo }
                state.$canRedo.withLock { $0 = undoManager.canRedo }
            default: break
            }
            return .none
        }
        .ifLet(\.$navigation, action: \.navigation)
    }
}
