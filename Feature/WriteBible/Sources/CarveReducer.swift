//
//  CarveReducer.swift
//  Feature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import ComposableArchitecture

@Reducer
public struct CarveReducer {
    public init() { }

    public struct State: Equatable {
        public init() { }
        var text: String = "Hi"
    }

    public enum Action {
        case tapped
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .tapped:
                print(state)
                return .none
            }
        }
    }

}
