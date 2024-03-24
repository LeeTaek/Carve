//
//  TabCoordinator.swift
//  Carve
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import FeatureCarve
import FeatureSettings
import SwiftUI

import ComposableArchitecture
import TCACoordinators

@Reducer
struct TabCoordinator {
    struct TabBarContent: Equatable {
        let name: String
        let image: String
        let tag: Int
    }
    
    
    struct State: Equatable {
        @BindingState public var currentActiveTab = 0
        var tabBarContents: [TabBarContent]
        var carve: CarveCoordinator.State
        var settings: SettingsCoordinator.State
        var isHidden: SwiftUI.Visibility = .automatic
        
        static let initialState = State(
            tabBarContents: [
                TabBarContent(name: "새기다", image: "carve", tag: 0),
                TabBarContent(name: "설정", image: "settings", tag: 1)
            ],
            carve: .initialState,
            settings: .initialState
        )
    }

    enum Action: BindableAction {
        case binding(BindingAction<TabCoordinator.State>)
        case carve(CarveCoordinator.Action)
        case settings(SettingsCoordinator.Action)
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Scope(
            state: \.carve,
            action: /Action.carve) {
                CarveCoordinator()
            }
        Scope(
            state: \.settings,
            action: /Action.settings) {
                SettingsCoordinator()
            }
        
        Reduce { state, action in
            switch action {
            case .carve(.routeAction(_, action: .carve(.view(.isScrollDown(let isScroll))))):
                state.isHidden = isScroll ? .hidden : .automatic
                return .none
            default:
                return .none
            }
        }
    }

}
