//
//  AppearanceSettingsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces

import ComposableArchitecture

/// 화면 모드 설정 — 시스템 설정 · 라이트 · 다크.
///
/// 값은 `@Shared(.appearanceMode)` 에 있다. 앱 루트 화면(`AppCoordinatorView`)이 같은 키를 읽으므로 여기서 쓰면 곧바로 반영된다.
/// 고른 값은 상태에 두지 않고 화면이 같은 키를 읽어 보여 준다. `SettingsFeature.Path` 가 `Hashable` 상태를 요구하고
/// `Shared` 는 `Hashable` 이 아니기 때문이다.
@Reducer
public struct AppearanceSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()

        public init() { }
    }

    public enum Action: ViewAction {
        case view(View)

        public enum View {
            case setAppearanceMode(AppearanceMode)
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.setAppearanceMode(let mode)):
                @Shared(.appearanceMode) var appearanceMode: AppearanceMode
                $appearanceMode.withLock { $0 = mode }
            }
            return .none
        }
    }
}
