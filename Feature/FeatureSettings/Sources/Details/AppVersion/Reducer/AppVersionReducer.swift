//
//  AppVersionReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct AppVersionReducer {
    public init() { }
    
    @ObservableState
    public struct State: Equatable, Hashable {
        public static let initialState = Self()
        public var path = StackState<Path.State>()
        public var iCloudIsOn: Bool = true
    }
    public enum Action {
        case path(StackActionOf<Path>)
        case pushToLisence
        case setiCloud(Bool)
    }
    
    @Reducer(state: .equatable, .hashable)
    public enum Path {
        case lisence(LisenceReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case.pushToLisence:
                state.path.append(.lisence(.initialState))
            case .setiCloud(let isOn):
                state.iCloudIsOn = isOn
            default: break
            }
            return .none
        }
        .forEach(\.path, action: \.path)
    }
}
