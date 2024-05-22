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
    public struct State: Equatable {
        
    }
    public enum Action {
        case setiCloud
    }
    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            default: break
            }
            return .none
        }
    }
}
