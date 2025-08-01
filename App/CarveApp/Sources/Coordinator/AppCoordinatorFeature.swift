//
//  AppCoordinatorFeature.swift
//  Carve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import CarveFeature
import SettingsFeature

import ComposableArchitecture

@Reducer
public struct AppCoordinatorFeature {
    @ObservableState
    public struct State {
        public static var initialState = Self()
        @Presents public var path: Path.State? = .launchProgress(.initialState)
    }
    public enum Action {
        case path(PresentationAction<Path.Action>)
    }
    
    @Reducer
    public enum Path {
        case launchProgress(LaunchProgressFeature)
        case carve(CarveNavigationFeature)
        case settings(SettingsFeature)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .path(.presented(.launchProgress(.syncCompleted))):
                state.path = .carve(.initialState)
            case .path(.presented(.carve(.view(.moveToSetting)))):
                state.path = .settings(.initialState)
            case .path(.presented(.settings(.view(.backToCarve)))):
                state.path = .carve(.initialState)
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}
