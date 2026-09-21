//
//  SettingsFeature.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Foundation

import ComposableArchitecture

@Reducer
public struct SettingsFeature {
    public init() { }
    @ObservableState
    public struct State: Equatable {
        public static let initialState = Self()
        @Presents public var path: Path.State? = .iCloud(.initialState)
        /// 광고 개인정보 옵션 항목을 보일지. 동의가 필요한 지역(EEA·영국·스위스 등)에서만 true.
        public var isPrivacyOptionsRequired = false
        /// 사이드바에서 선택 표시할 행. 상세 화면의 상태가 바뀌어도 같은 화면이면 같은 행이다.
        public var selectedSidebarItem: SidebarItem? { path?.sidebarItem }

        public static func initialState(path: Path.State?) -> Self {
            var state = Self()
            state.path = path
            return state
        }
    }
    public enum Action: ViewAction {
        case delegate(Delegate)
        case path(PresentationAction<Path.Action>)
        /// 사이드바에서 행을 고름. 보고 있는 화면의 행이면 상세 상태를 그대로 둔다.
        case selectSidebarItem(SidebarItem?)
        case view(View)

        public enum Delegate {
            case restartFirstRunGuide
        }
        
        public enum View {
            case backToCarve
            case onAppear
            /// 광고 개인정보 옵션 폼 열기
            case privacyOptionsTapped
        }
    }
    
    @Reducer
    public enum Path {
        case iCloud(CloudSettingsFeature)
        /// 필사 캔버스 — 단일 Canvas flag 토글 (설계 §13 Phase 3 (3/3)).
        case canvas(CanvasSettingsFeature)
        /// 위젯에 표시할 말씀(시안 N7 · N8).
        case widget(WidgetSettingsFeature)
        /// 화면 모드 — 시스템 설정 · 라이트 · 다크.
        case appearance(AppearanceSettingsFeature)
        /// 필사 사용법과 첫 안내 다시 보기.
        case help(HelpFeature)
        /// 앱 업데이트 변경 사항.
        case patchnote(PatchnoteFeature)
        case sendFeedback(SendFeedbackFeature)
        case appVersion(AppVersionFeature)
        /// 광고 제거 구매 · 복원(시안 K4).
        case removeAds(RemoveAdsFeature)
    }

    /// 사이드바 행 — 경로 상태에서 상세 화면의 상태를 빼고 어느 화면인지만 남긴 값.
    ///
    /// ⚠️ 사이드바 `List(selection:)` 에 경로 상태를 그대로 쓰지 않는다. 행의 값이 처음 상태(`.canvas(.initialState)`)라
    ///    상세 화면의 상태가 바뀌는 순간(필사 캔버스 토글 · 광고 제거 상품 불러오기) 선택 값과 달라져 선택 표시가 풀렸다.
    public enum SidebarItem: Hashable, CaseIterable, Sendable {
        case iCloud
        case canvas
        case widget
        case appearance
        case help
        case patchnote
        case sendFeedback
        case appVersion
        case removeAds
    }
    
    @Dependency(\.adConsentClient) var adConsentClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                state.isPrivacyOptionsRequired = MainActor.assumeIsolated {
                    adConsentClient.isPrivacyOptionsRequired
                }
            case .view(.privacyOptionsTapped):
                return .run { _ in
                    // 폼을 닫거나 띄우지 못해도 설정 화면 상태는 바뀌지 않는다.
                    try? await adConsentClient.presentPrivacyOptions()
                }
            case .selectSidebarItem(let item):
                // 보고 있는 화면의 행을 다시 골라도 상세 상태(불러온 상품 · 쓰던 의견)를 처음으로 되돌리지 않는다.
                guard item != state.selectedSidebarItem else { return .none }
                state.path = item?.initialPath
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

extension SettingsFeature.Path.State {
    /// 이 화면을 여는 사이드바 행.
    var sidebarItem: SettingsFeature.SidebarItem {
        switch self {
        case .iCloud: .iCloud
        case .canvas: .canvas
        case .widget: .widget
        case .appearance: .appearance
        case .help: .help
        case .patchnote: .patchnote
        case .sendFeedback: .sendFeedback
        case .appVersion: .appVersion
        case .removeAds: .removeAds
        }
    }
}

extension SettingsFeature.SidebarItem {
    /// 행을 골랐을 때 여는 화면의 처음 상태.
    var initialPath: SettingsFeature.Path.State {
        switch self {
        case .iCloud: .iCloud(.initialState)
        case .canvas: .canvas(.initialState)
        case .widget: .widget(.initialState)
        case .appearance: .appearance(.initialState)
        case .help: .help(.initialState)
        case .patchnote: .patchnote(.initialState)
        case .sendFeedback: .sendFeedback(.initialState)
        case .appVersion: .appVersion(.initialState)
        case .removeAds: .removeAds(.initialState)
        }
    }
}
