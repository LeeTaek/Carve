//
//  FirstRunGuideFeature.swift
//  CarveFeature
//
//  Created by Codex on 9/11/26.
//

import ComposableArchitecture

/// 최초 필사 안내 팝업의 상태와 완료 이벤트를 관리한다.
@Reducer
public struct FirstRunGuideFeature {
    public init() { }

    @ObservableState
    public struct State: Equatable {
        public static let initialState = Self()
    }

    public enum Action: ViewAction {
        case delegate(Delegate)
        case view(View)

        public enum Delegate {
            case finished
        }

        public enum View {
            case startTapped
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.startTapped):
                return .send(.delegate(.finished))
            case .delegate:
                return .none
            }
        }
    }
}
