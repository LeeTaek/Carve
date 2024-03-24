//
//  TabScreen.swift
//  Carve
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import FeatureCarve
import FeatureSettings

import ComposableArchitecture
import TCACoordinators

@Reducer
struct TabScreen {
    enum State: Equatable {
    case carve(CarveCoordinator.State)
    case settings(SettingsCoordinator.State)
    }
    
    enum Action {
        case carve(CarveCoordinator.Action)
        case settings(SettingsCoordinator.Action)
    }
    
    
    var body: some Reducer<State, Action> {
        Scope(
            state: /State.carve,
            action: /Action.carve
        ) {
            CarveCoordinator()
        }
        Scope(
            state: /State.settings,
            action: /Action.settings
        ) {
            SettingsCoordinator()
        }
    }
}
