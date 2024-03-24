//
//  SettingsReducer.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct SettingsReducer {
    public init() { }

    public struct State: Equatable {
        public init() { }
        public let id: UUID = UUID()
        static let initialState = Self()

        var text: String = "Settings"
    }

    public enum Action {
        case tapped
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .tapped:
                print(state)
                return .none
            }
        }
    }

}
