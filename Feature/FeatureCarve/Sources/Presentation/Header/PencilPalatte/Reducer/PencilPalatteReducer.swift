//
//  PencilPalatteReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct PencilPalatteReducer {
    @ObservableState
    public struct State {
        
    }
    public enum Action {
    
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            return .none
        }
        
    }
}
