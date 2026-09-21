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
        /// 올가미 도구를 쓰는 중인가. `pencilConfig.pencilType` 의 `.monoline`(지우개) sentinel 보다 **우선**한다 (올가미 설계 §4-1).
        ///
        /// 앱 실행 동안만 유지한다(`.inMemory`) — 올가미인 채로 앱을 닫으면 다음 실행에서 펜슬을 대도 글씨가 써지지 않아
        /// 사용자에게는 고장으로 읽힌다. 지우개와 달리 화면에 남는 흔적도 없다.
        @Shared(.inMemory("isLassoSelected")) public var isLassoSelected: Bool = false
        /// 올가미를 쓸 수 있는가. **단일 Canvas 경로에서만 true** 다 (올가미 설계 §4-8) —
        /// N-Canvas 롤백 경로(`CanvasView`)는 절마다 캔버스가 따로라 장 단위 선택·이동이 성립하지 않는다.
        /// 값은 `delegatesUndoToCanvas` 와 같은 자리에서 `CarveDetailFeature` 가 정한다.
        public var isLassoAvailable: Bool = false

        /// 굵기 팝오버를 열 칸. 팔레트 글자가 보여 주는 **펜의 현재 굵기**와 같은 칸을 먼저 찾고,
        /// 없으면 선택 칸으로 간다 — 글자는 `pencilConfig` 를, 선택 표시는 `selectedWidthIndex` 를 읽어
        /// 둘이 어긋난 채로 열리면 사용자는 방금 본 값과 다른 칸을 만지게 된다.
        public var editingWidthIndex: Int {
            lineWidths.firstIndex(of: pencilConfig.lineWidth) ?? selectedWidthIndex
        }

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
            case selectLasso
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
                // 펜 · 지우개를 고르면 올가미에서 빠져나온다. `pencilType` 은 그대로 두므로 마지막 잉크가 유지된다.
                state.$isLassoSelected.withLock { $0 = false }
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.$pencilConfig.withLock { $0.pencilType = type }
                }
            case .view(.selectLasso):
                guard state.isLassoAvailable else { return .none }
                state.$isLassoSelected.withLock { $0 = true }
            case .view(.setLineWidth(let index)):
                state.$selectedWidthIndex.withLock { $0 = index }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[index] }
            case .view(.setPopoverPoint(let point)):
                state.popoverPoint = point
            case .view(.popoverColor(let index)):
                // 칸 번호는 저장된 사용자 값에서 온다 — 배열보다 크면 열지 않는다.
                guard index < state.palatteColors.count else { return .none }
                state.navigation = .colorPalatte(.init(index: index, color: state.palatteColors[index]))
            case .view(.popoverLineWidth(let index)):
                guard index < state.lineWidths.count else { return .none }
                state.navigation = .lineWidthPalatte(.init(lineWidth: state.lineWidths[index], index: index))
            case .navigation(.dismiss):
                // 닫을 때 다시 맞추지 않는다. 색 · 굵기 팝오버(시안 P1 · P2)가 고르는 즉시 `pencilConfig` 까지 쓰므로,
                // 여기서 선택 칸 값으로 덮으면 **사용자가 방금 조절한 값이 닫는 순간 되돌아간다**
                // (펜 1.0 mm 인 채로 팝오버를 열었다 닫으면 선택 칸의 0.5 mm 로 바뀌던 동작).
                break
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
