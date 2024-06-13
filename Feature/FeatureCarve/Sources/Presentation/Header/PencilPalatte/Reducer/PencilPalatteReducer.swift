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
        public var palatteColors: [UIColor]
        public var palattePencilType: PKInkingTool.InkType
        public static var initialState = State(palatteColors: [.black, .blue, .red],
                                               palattePencilType: .pen
        )
    }
    public enum Action {
        case setConfigPencilColor(ChoosedColor)
        case setConfigPencilType(PKInkingTool.InkType)
        case changePencilColor(index: Int, color: UIColor)
        case setColor(UIColor)
        case setPencilType(PKInkingTool.InkType)
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setConfigPencilColor(let color):
                state.pencilConfig.color = color
            case .setConfigPencilType(let type):
                state.pencilConfig.pencilType = type
            case let .changePencilColor(index, color):
                state.palatteColors[index] = color
            case .setColor(let color):
                guard let index = state.palatteColors.firstIndex(of: color),
                      let choosedColor = ChoosedColor(rawValue: index)
                else { return .none }
                withAnimation {
                    state.pencilConfig.color = choosedColor
                }
            case .setPencilType(let type):
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.pencilConfig.pencilType = type
                }
            }
            return .none
        }
    }
}
