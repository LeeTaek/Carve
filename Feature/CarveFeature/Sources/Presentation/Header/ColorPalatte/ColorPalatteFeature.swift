//
//  ColorPalatteFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct ColorPalatteFeature {
    @ObservableState
    public struct State {
        @Shared(.appStorage("palatteColorSet")) public var palatteColors: [CodableColor] = []
        public var index: Int
        public var selectedColor: CodableColor
        public var alpha: CGFloat = 1
        public var colors: [UIColor] = [.black, .red, .yellow, .blue, .green, .brown, .purple, .cyan]
        public init(index: Int, color: CodableColor) {
            self.index = index
            self.selectedColor = color
            self.alpha = color.color.alphaValue
        }
    }
    public enum Action: ViewAction {
        case view(View)
        case setAlpha(CGFloat)

        public enum View {
            case setColor(UIColor)
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.setColor(let color)):
                let selectedColor = color.withAlphaComponent(state.alpha)
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.selectedColor = .init(color: selectedColor)
                    state.$palatteColors.withLock { $0[state.index] = .init(color: selectedColor) }
                }
            case .setAlpha(let alpha):
                state.alpha = alpha
            }
            return .none
        }
    }
}
