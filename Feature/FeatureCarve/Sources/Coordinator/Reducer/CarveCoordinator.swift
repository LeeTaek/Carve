//
//  CarveCoordinator.swift
//  Feature
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import Foundation

import ComposableArchitecture
import TCACoordinators

@Reducer
public struct CarveCoordinator {
    public init() { }

    public struct State: Equatable, IndexedRouterState {
        public var id: UUID
        public var routes: [Route<CarveScreen.State>]

        public static let initialState = State(
            id:.init(),
            routes: [.root(.carve(.initialState))]
        )
    }

    public enum Action: IndexedRouterAction {
        case routeAction(Int, action: CarveScreen.Action)
        case updateRoutes([Route<CarveScreen.State>])
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
        .forEachRoute {
            CarveScreen()
        }
    }

}
