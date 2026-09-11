//
//  PatchnoteFeature.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import ComposableArchitecture

/// 릴리스 변경 사항을 보여주는 패치노트.
@Reducer
public struct PatchnoteFeature {
    public init() { }

    @ObservableState
    public struct State: Equatable, Hashable {
        public static let initialState = Self()
    }

    public enum Action: ViewAction {
        case delegate(Delegate)
        case view(View)

        public enum Delegate {
            case close
            case showHelp
        }

        public enum View {
            case closeTapped
            case helpTapped
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.closeTapped):
                return .send(.delegate(.close))
            case .view(.helpTapped):
                return .send(.delegate(.showHelp))
            case .delegate:
                return .none
            }
        }
    }
}
