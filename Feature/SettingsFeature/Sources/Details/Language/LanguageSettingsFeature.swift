//
//  LanguageSettingsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ComposableArchitecture

/// 앱 언어 — 지금 화면 언어를 보여 주고, iPad 설정 앱의 이 앱 화면(「언어」 항목이 있는 곳)을 연다(영어 현지화 결정 20).
///
/// 언어는 앱 안에 따로 저장하지 않고 iOS 의 앱별 언어를 그대로 쓴다. 바꾸면 iOS 가 앱을 새로 시작하므로 화면 · 권 이름 · 날짜 서식이
/// 한꺼번에 바뀐다. 앱 안에서 같은 키(`AppleLanguages`)를 써도 효과는 같지만, 그때는 iOS 가 앱을 끝내 주지 않아 사용자가 직접 다시 열어야 해서 쓰지 않는다.
/// 기기에 선호 언어가 하나뿐이어도 설정 앱에 「언어」 항목이 보이도록 앱 Info.plist 에 `UIPrefersShowingLanguageSettings` 를 켠다.
@Reducer
public struct LanguageSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        public static let initialState = Self()

        public init() { }
    }

    public enum Action: ViewAction {
        case view(View)

        public enum View {
            /// 「iPad 설정에서 바꾸기」 — 설정 앱의 이 앱 화면을 연다.
            case openSystemSettingsTapped
        }
    }

    @Dependency(\.openURL) var openURL

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.openSystemSettingsTapped):
                return .run { [openURL] _ in
                    // 설정 앱 주소는 UIKit 값이라 리듀서 밖(`AppLanguage.swift`)에서 읽는다.
                    guard let url = await AppSettingsURL.current() else { return }
                    _ = await openURL(url)
                }
            }
        }
    }
}
