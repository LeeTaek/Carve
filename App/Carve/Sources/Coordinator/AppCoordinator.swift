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
    public struct State {
        public static var initialState = Self()
        @Presents public var path: Path.State? = .carve(.initialState)
    }
    public enum Action {
        case path(PresentationAction<Path.Action>)
    }
    
    @Reducer
    public enum Path {
        case carve(CarveReducer)
        case settings(SettingsReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .path(.presented(.carve(.view(.moveToSetting)))):
                state.path = .settings(.initialState)
            case .path(.presented(.settings(.backToCarve))):
                state.path = .carve(.initialState)
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}
