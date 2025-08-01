//
//  DrawingChartFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct DrawingChartFeature {
    public init() { }
    @ObservableState
    public struct State {
        public static let initialState = Self()
    }
    public enum Action: ViewAction {
        case view(View)
        
        public enum View {
            
        }
    }
    public var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
