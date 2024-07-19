//
//  LisenceReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct LisenceReducer {
    public init() { }
    
    @ObservableState
    public struct State {
        public static let initialState = Self()
    }
    public enum Action {
        case present
    }
    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            default: break
            }
            return .none
        }
    }
}
