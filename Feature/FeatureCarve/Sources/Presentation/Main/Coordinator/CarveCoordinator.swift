//
//  CarveCoordinator.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture
import TCACoordinators

@Reducer(state: .equatable)
public enum CarveScreen {
    case carve(CarveReducer)
}

@Reducer
public struct CarveCoordinator {
    public init() { }
    
    public struct State: Equatable {
        var routes: [Route<CarveScreen.State>]
        public static let initialState = State(routes: [.root(.carve(.initialState), embedInNavigationView: false)])
    }
    public enum Action {
        case router(IndexedRouterActionOf<CarveScreen>)
        case moveToSetting
    }
    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .router(.routeAction(_, action: .carve(.view(.moveToSetting)))):
                return .run { send in
                    await send(.moveToSetting)
                }
                
            default: break
            }
            return .none
        }
        .forEachRoute(\.routes, action: \.router)
    }
}
