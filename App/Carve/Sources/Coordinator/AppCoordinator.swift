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
import TCACoordinators

@Reducer
public struct AppCoordinator {
    @ObservableState
    public enum State: Equatable {
        public static var initialState: Self = .carve(.initialState)
        case carve(CarveCoordinator.State)
        case settings(SettingsCoordinator.State)
    }
    public enum Action {
        case carve(CarveCoordinator.Action)
        case settings(SettingsCoordinator.Action)
        
        case present(AppCoordinator.State)
    }
    public var body: some Reducer<State, Action> {
        Scope(state: \.carve, action: \.carve) {
            CarveCoordinator()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsCoordinator()
        }
        
        Reduce { state, action in
            switch action {
            case .carve(.moveToSetting):
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
