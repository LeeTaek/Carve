//
//  SettingsCoordinator.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture
import TCACoordinators

@Reducer
public struct SettingsCoordinator {
    public init() { }

    public struct State: Equatable, IndexedRouterState {
        public var id: UUID
        public var routes: [Route<SettingsScreen.State>]

        public static let initialState = State(
            id:.init(),
            routes: [.root(.carve(.initialState))]
        )
    }

    public enum Action: IndexedRouterAction {
        case routeAction(Int, action: SettingsScreen.Action)
        case updateRoutes([Route<SettingsScreen.State>])
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .routeAction(_, action: .carve(.tapped)):
                state.routes.push(.carve(.init()))
                return .none
            default:
                return .none
            }
        }
        .forEachRoute {
            SettingsScreen()
        }
    }

}
