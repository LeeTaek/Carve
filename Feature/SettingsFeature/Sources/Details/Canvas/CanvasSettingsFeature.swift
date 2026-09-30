//
//  CanvasSettingsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

/// 필사 캔버스 설정 — 단일 Canvas feature flag 토글 (설계 §13 Phase 3 (3/3) · §10-3).
///
/// 값은 `SingleCanvasFlag.appStorageKey` 의 `UserDefaults` 에 있다. `CarveFeature` 는 같은 키를
/// `@Shared(.appStorage)` 로 관찰하므로 여기서 쓰면 곧바로 반영된다. 상태에 `@Shared` 를 두지 않는 이유는
/// `SettingsFeature.Path` 가 `Hashable` 상태를 요구하고 `Shared` 는 `Hashable` 이 아니기 때문이다.
@Reducer
public struct CanvasSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        /// flag 의 현재 값. 화면이 나타날 때 읽고, 토글이 바꾼다.
        public var isSingleCanvasEnabled: Bool = SingleCanvasFlag.defaultValue

        public init() { }
    }

    @Dependency(\.defaultAppStorage) private var appStorage

    public enum Action: ViewAction {
        case view(View)

        @CasePathable
        public enum View {
            case onAppear
            case setSingleCanvasEnabled(Bool)
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                // ⚠️ `bool(forKey:)` 는 키가 없으면 무조건 false 다 — 기본값이 true 인 지금은
                // 그대로 쓰면 앱은 단일 Canvas 인데 토글만 OFF 로 보인다. 키의 존재를 먼저 본다.
                state.isSingleCanvasEnabled = appStorage.object(forKey: SingleCanvasFlag.appStorageKey) == nil
                    ? SingleCanvasFlag.defaultValue
                    : appStorage.bool(forKey: SingleCanvasFlag.appStorageKey)
            case .view(.setSingleCanvasEnabled(let isOn)):
                state.isSingleCanvasEnabled = isOn
                appStorage.set(isOn, forKey: SingleCanvasFlag.appStorageKey)
            }
            return .none
        }
    }
}
