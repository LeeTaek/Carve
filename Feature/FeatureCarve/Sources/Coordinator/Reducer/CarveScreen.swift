//
//  CarveScreen.swift
//  Feature
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct CarveScreen {
    public enum State: Equatable, Identifiable {
        case carve(CarveReducer.State)

        public var id: UUID {
            switch self {
            case .carve(let state):
                return state.id
            }
        }
    }

    public enum Action {
        case carve(CarveReducer.Action)
    }

    public var body: some Reducer<State, Action> {
        Scope( state: /State.carve,
               action: /Action.carve) {
            CarveReducer()
        }
    }
}
