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
        @Presents public var path: Path.State? = .iCloud(.initialState)
    }
    public enum Action {
        case path(PresentationAction<Path.Action>)
        case push(Path.State?)
        case backToCarve
    }
    
    @Reducer(state: .hashable)
    public enum Path {
        case iCloud(CloudSettingsReducer)
        case sendFeedback(SendFeedbackReducer)
        case appVersion(AppVersionReducer)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .push(let path):
                state.path = path
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }

}
