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

@Reducer(state: .equatable)
public enum DetailSettings: CaseIterable, Identifiable {
    public var id: String {
        switch self {
        case .iCloud:
            return "iCloud"
        case .appVersion:
            return "appVersion"
        case .lisence:
            return "lisence"
        }
    }
    case iCloud
    case appVersion
    case lisence
}


@Reducer
public struct SettingsReducer {
    public init() { }
    
    @ObservableState
    public struct State: Equatable {
        static let initialState = Self()
        public var selected: DetailSettings?
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case presentDetail(DetailSettings)
        case backToCarve
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .presentDetail(let settings):
                state.selected = settings
            default:
                break
            }
            return .none
        }
    }

}
