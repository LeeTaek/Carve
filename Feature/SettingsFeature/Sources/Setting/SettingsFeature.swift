//
//  SettingsFeature.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation

import ComposableArchitecture

@Reducer
public struct SettingsFeature {
    public init() { }
    @ObservableState
    public struct State {
        public static let initialState = Self()
        @Presents public var path: Path.State? = .iCloud(.initialState)
    }
    public enum Action: ViewAction {
        case path(PresentationAction<Path.Action>)
        case push(Path.State?)
        case view(View)
        
        public enum View {
            case backToCarve
        }
    }
    
    @Reducer(state: .hashable)
    public enum Path {
        case iCloud(CloudSettingsFeature)
        /// 필사 캔버스 — 단일 Canvas flag 토글 (설계 §13 Phase 3 (3/3)).
        case canvas(CanvasSettingsFeature)
        case sendFeedback(SendFeedbackFeature)
        case appVersion(AppVersionFeature)
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
