//
//  LineWidthPalatteReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct LineWidthPalatteReducer {
    @ObservableState
    public struct State {
        @Shared(.appStorage("lineWidthSet")) public var lineWidths: [CGFloat] = []
        public let index: Int
        public var lineWidth: CGFloat
        
        public init(lineWidth: CGFloat, index: Int) {
            self.lineWidth = lineWidth
            self.index = index
        }
    }
    public enum Action {
        case setWidth(CGFloat)
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setWidth(let width) :
                state.lineWidth = width
                state.$lineWidths.withLock { $0[state.index] = width }
            }
            return .none
        }
    }
}
