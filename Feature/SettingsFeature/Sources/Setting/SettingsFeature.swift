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

        public static func initialState(path: Path.State?) -> Self {
            var state = Self()
            state.path = path
            return state
        }
    }
    public enum Action: ViewAction {
        case delegate(Delegate)
        case path(PresentationAction<Path.Action>)
        case push(Path.State?)
        case view(View)

        public enum Delegate {
            case restartFirstRunGuide
        }
        
        public enum View {
            case backToCarve
        }
    }
    
    @Reducer
    public enum Path {
        case iCloud(CloudSettingsFeature)
        /// 필사 캔버스 — 단일 Canvas flag 토글 (설계 §13 Phase 3 (3/3)).
        case canvas(CanvasSettingsFeature)
        /// 필사 사용법과 첫 안내 다시 보기.
        case help(HelpFeature)
        /// 앱 업데이트 변경 사항.
        case patchnote(PatchnoteFeature)
        case sendFeedback(SendFeedbackFeature)
        case appVersion(AppVersionFeature)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .push(let path):
                state.path = path
            case .path(.presented(.help(.delegate(.restartFirstRunGuide)))):
                return .send(.delegate(.restartFirstRunGuide))
            case .path(.presented(.patchnote(.delegate(.showHelp)))):
                state.path = .help(.initialState)
            case .path(.presented(.patchnote(.delegate(.close)))):
                state.path = nil
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }

}

extension SettingsFeature.Path.State: Hashable {}
