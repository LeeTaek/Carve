//
//  ColorPalatteReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct ColorPalatteReducer {
    @ObservableState
    public struct State {
        public static var initialState = State()
    }
    public enum Action {
        
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            return .none
        }
    }
}
