//
//  iCloudSettingReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct CloudSettingsReducer {
    public init() { }
    
    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        public var iCloudIsOn: Bool = true
    }
    public enum Action {
        case setiCloud(Bool)
        case removeAlliCloudData
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setiCloud(let ison):
                state.iCloudIsOn = ison
            default: break
            }
            return .none
        }
    }
}
