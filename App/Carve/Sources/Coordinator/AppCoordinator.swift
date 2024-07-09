//
//  AppCoordinator.swift
//  Carve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import FeatureCarve
import FeatureSettings

import ComposableArchitecture

@Reducer
public struct AppCoordinator {
    @ObservableState
    public enum State {
        public static var initialState: Self = .carve(.initialState)
        case carve(CarveReducer.State)
        case settings(SettingsReducer.State)
    }
    public enum Action {
        case carve(CarveReducer.Action)
        case settings(SettingsReducer.Action)
        case present(AppCoordinator.State)
    }
    public var body: some Reducer<State, Action> {
        Scope(state: \.carve, action: \.carve) {
            CarveReducer()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsReducer()
        }
        Reduce { state, action in
            switch action {
            case .carve(.view(.moveToSetting)):
                return .run { send in
                    await send(.present(.settings(.initialState)))
                }
            case .settings(.backToCarve):
                return .run { send in
                    await send(.present(.carve(.initialState)))
                }
            case .present(let screen):
                state = screen
            default: break
            }
            return .none
        }
    }
}
