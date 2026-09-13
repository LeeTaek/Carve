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

    static let pageCount = 4

    @ObservableState
    public struct State: Equatable {
        public static let initialState = Self()
        /// 최초 안내에서 현재 표시하는 항목의 0 기반 위치다.
        public var currentPage = 0
    }

    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)

        public enum Delegate {
            case finished
        }

        public enum View {
            /// 다음 안내를 표시하거나 마지막 안내를 완료할 때 발생한다.
            case nextTapped
            /// 남은 안내를 건너뛰고 필사를 시작할 때 발생한다.
            case skipTapped
        }
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .view(.nextTapped):
                guard state.currentPage == Self.pageCount - 1 else {
                    state.currentPage += 1
                    return .none
                }
                return .send(.delegate(.finished))
            case .view(.skipTapped):
                return .send(.delegate(.finished))
            case .binding, .delegate:
                return .none
            }
        }
    }
}
