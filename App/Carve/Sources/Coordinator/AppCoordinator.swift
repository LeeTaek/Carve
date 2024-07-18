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
        @Presents public var destination: Destination.State? = .carve(.initialState)
        public init(destination: AppCoordinator.Destination.State) {
            self.destination = destination
        }
    }
    public enum Action {
        case destination(PresentationAction<Destination.Action>)
    }
    
    @Reducer
    public enum Destination {
        case carve(CarveReducer)
        case settings(SettingsReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.carve(.view(.moveToSetting)))):
                state.destination = .settings(.initialState)
            case .destination(.presented(.settings(.backToCarve))):
                state.destination = .carve(.initialState)
            default: break
            }
            return .none
        }
        .ifLet(\.$destination, action: \.destination)
    }
}
