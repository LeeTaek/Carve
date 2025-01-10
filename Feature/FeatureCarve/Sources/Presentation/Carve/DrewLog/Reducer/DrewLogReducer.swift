//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Domain

import ComposableArchitecture

@Reducer
public struct DrewLogReducer {
    public struct State {
        public static let initialState = State()
    }
    public enum Action {
        case dismiss
    }
    public var body: some Reducer<State, Action> {
        Reduce { _, _ in
            return .none
        }
    }
}
