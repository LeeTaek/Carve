//
//  SentenceSettingsReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct SentenceSettingsReducer {
    @ObservableState
    public struct State: Equatable {
        public static var initialState = Self()
    }
    public enum Action {
        
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            return .none
        }
    }
    
}
