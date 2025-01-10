//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core

import ComposableArchitecture

@Reducer
public struct DrewLogReducer {
    public struct State {
        public static let initialState = State()
    }
    public enum Action {
//        case view(ViewAction)
//        case inner(InnerAction)
    }
//    public enum ViewAction: Equatable {
//    }
//    
//    public enum InnerAction: Equatable {
//    }
    public var body: some Reducer<State, Action> {
        Reduce { _, _ in
            return .none
        }
    }
}
