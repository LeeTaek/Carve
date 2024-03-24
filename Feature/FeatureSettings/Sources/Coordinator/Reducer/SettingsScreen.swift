//
//  SettingsScreen.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct SettingsScreen {
    public enum State: Equatable, Identifiable {
        case carve(SettingsReducer.State)

        public var id: UUID {
            switch self {
            case .carve(let state):
                return state.id
            }
        }
    }

    public enum Action {
        case carve(SettingsReducer.Action)
    }

    public var body: some Reducer<State, Action> {
        Scope( state: /State.carve,
               action: /Action.carve) {
            SettingsReducer()
        }
    }
}
