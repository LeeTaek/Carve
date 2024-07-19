//
//  SettingsReducer.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation

import ComposableArchitecture

@Reducer
public struct SettingsReducer {
    public init() { }
    @ObservableState
    public struct State {
        public static let initialState = Self()
        public var path = StackState<Path.State>()
    }
    public enum Action {
        case path(StackActionOf<Path>)
        case pushToiCloudSettings
        case pushToAppVersion
        case pushToLisence
        case backToCarve
    }
    @Reducer
    public enum Path {
        case iCloud(CloudSettingsReducer)
        case appVersion(AppVersionReducer)
        case lisence(LisenceReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .pushToiCloudSettings:
                state.path.append(.iCloud(.initialState))
            case .pushToAppVersion:
                state.path.append(.appVersion(.initialState))
            case .pushToLisence:
                state.path.append(.lisence(.initialState))
            default: break
            }
            return .none
        }
        .forEach(\.path, action: \.path)
    }

}
