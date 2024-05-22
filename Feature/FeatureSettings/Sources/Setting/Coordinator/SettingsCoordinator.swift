//
//  SettingsCoordinator.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation

import ComposableArchitecture
import TCACoordinators

@Reducer(state: .equatable)
public enum SettingsScreen {
    case settings(SettingsReducer)
    case icloud(CloudSettingsReducer)
}

@Reducer
public struct SettingsCoordinator {
    public init() { }
    @ObservableState
    public struct State: Equatable {
        var routes: [Route<SettingsScreen.State>]
        public static let initialState = State(routes: [.root(.settings(.initialState), embedInNavigationView: true)])
    }
    public enum Action {
        case router(IndexedRouterActionOf<SettingsScreen>)
        case backToCarve
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .router(.routeAction(_, .settings(.backToCarve))):
                return .run { send in
                    await send(.backToCarve)
                }
            case .router(.routeAction(_, action: .settings(.presentDetail(let detailSetting)))):
                switch detailSetting {
                case .iCloud:
                    state.routes.push(.icloud(.init()))
                default: break
                }
            default: break
            }
            return .none
        }
        .forEachRoute(\.routes, action: \.router)
    }
}
