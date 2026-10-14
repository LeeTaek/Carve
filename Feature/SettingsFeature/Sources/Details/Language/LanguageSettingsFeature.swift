//
//  LanguageSettingsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces

import ComposableArchitecture

/// 앱 언어 — 시스템 설정 따름 · 한국어 · English 를 고르면 앱을 다시 시작하지 않고 바로 바꾼다(보관함 「Carve 앱 언어 즉시 전환」 단계 1).
///
/// - 저장: iOS 앱별 언어와 같은 값(앱 도메인 `AppleLanguages`)에 쓴다 — 설정 앱 › 새기다 › 언어와 같은 값이라 둘 중 어디서 바꿔도 같다
///   (단일 진실, 2026-10-13 결정). 다음 실행부터 iOS 가 앱 전체에 그 언어를 쓴다.
/// - 지금 실행: 고른 언어를 `appLanguageOverride` 에 넣는다. 앱 루트가 환경 `locale` 을 바꿔 키 기반 문구가 바로 바뀐다.
///   미리 만든 문자열도 뷰는 환경 `locale`, 리듀서 · effect 는 `AppLanguage.displayLocale()` 로 만들어 바로 따라온다(단계 2 · 3).
///   리듀서가 상태에 담은 문구(떠 있는 대화상자 · 결과 한 줄)는 다시 만들 때까지 만든 순간의 언어로 남는다.
/// - 「iPad 설정에서 바꾸기」 는 보조로 남긴다 — 설정 앱에서 바꾸면 iOS 가 앱을 종료해 새 언어로 다시 연다.
///   기기에 선호 언어가 하나뿐이어도 그 항목이 보이도록 앱 Info.plist 에 `UIPrefersShowingLanguageSettings` 를 켠다.
@Reducer
public struct LanguageSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        public static let initialState = Self()

        /// 저장된 고르기. 화면이 뜰 때 읽는다.
        public var selection: AppLanguageSelection

        public init(selection: AppLanguageSelection = .system) {
            self.selection = selection
        }
    }

    public enum Action: ViewAction {
        case view(View)

        public enum View {
            /// 화면이 뜸 — 저장된 고르기를 읽는다.
            case onAppear
            /// 언어를 고름 — 저장하고 지금 실행의 화면 언어를 바로 바꾼다.
            case selectionChanged(AppLanguageSelection)
            /// 「iPad 설정에서 바꾸기」 — 설정 앱의 이 앱 화면을 연다.
            case openSystemSettingsTapped
        }
    }

    @Dependency(\.appLanguageClient) var appLanguageClient
    @Dependency(\.openURL) var openURL

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                state.selection = appLanguageClient.selection()
                return .none

            case .view(.selectionChanged(let selection)):
                guard selection != state.selection else { return .none }
                state.selection = selection
                appLanguageClient.save(selection)
                // 저장 바로 뒤의 iOS 선호 언어로 고른다 — 시스템 설정이면 기기 언어다.
                let language = appLanguageClient.resolvedLanguage()
                @Shared(.appLanguageOverride) var languageOverride: AppLanguage?
                $languageOverride.withLock { $0 = language }
                return .none

            case .view(.openSystemSettingsTapped):
                return .run { [openURL] _ in
                    // 설정 앱 주소는 UIKit 값이라 리듀서 밖(`LanguageSettingsSupport.swift`)에서 읽는다.
                    guard let url = await AppSettingsURL.current() else { return }
                    _ = await openURL(url)
                }
            }
        }
    }
}
