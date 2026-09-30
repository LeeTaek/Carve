//
//  HelpFeature.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import ComposableArchitecture

/// 설정에서 다시 열 수 있는 필사 도움말.
@Reducer
public struct HelpFeature {
    public init() { }

    @ObservableState
    public struct State: Equatable, Hashable {
        public static let initialState = Self()
    }

    public enum Action: ViewAction {
        case delegate(Delegate)
        case view(View)

        public enum Delegate {
            case restartFirstRunGuide
        }

        public enum View {
            case restartFirstRunGuideTapped
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.restartFirstRunGuideTapped):
                return .send(.delegate(.restartFirstRunGuide))
            case .delegate:
                return .none
            }
        }
    }
}
