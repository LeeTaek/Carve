//
//  DrewLogFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import CarveToolkit

import ComposableArchitecture

@Reducer
public struct DrewLogFeature {
    public struct State {
        public static let initialState = State()
    }
    public enum Action {

    }
    public var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
