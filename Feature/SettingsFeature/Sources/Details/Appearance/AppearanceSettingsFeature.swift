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
/// ⚠️ 고른 값은 상태에 두지 않고 화면이 같은 키를 읽어 보여 준다. 상태가 모드에 따라 달라지면 `SettingsFeature.Path.State` 가
/// 사이드바 행의 값(`.appearance(.initialState)`)과 같지 않게 되어 행 선택 표시가 풀린다. `Shared` 는 `Hashable` 도 아니다.
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
