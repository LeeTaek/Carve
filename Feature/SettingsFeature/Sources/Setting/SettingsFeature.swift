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
    public struct State {
        public static let initialState = Self()
        @Presents public var path: Path.State? = .iCloud(.initialState)
        /// 광고 개인정보 옵션 항목을 보일지. 동의가 필요한 지역(EEA·영국·스위스 등)에서만 true.
        public var isPrivacyOptionsRequired = false
        /// 이번 실행의 iCloud 연결이 C14 게이트로 보류됐는가(정책 §12-6 C14 ③ · D2 — 설정 항목으로도 안내한다). 화면이 뜰 때 읽는다.
        public var isConnectionHeld = false

        public static func initialState(path: Path.State?) -> Self {
            var state = Self()
            state.path = path
            return state
        }
    }
    public enum Action: ViewAction {
        case delegate(Delegate)
        case path(PresentationAction<Path.Action>)
        case push(Path.State?)
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
        /// 보이지 않게 남은 필기 — 개수 · 용량 · 목록(정책 §12-6 구현 순서 ④, 읽기 전용).
        case draftRecovery(DraftRecoveryFeature)
        /// 필사 캔버스 — 단일 Canvas flag 토글 (설계 §13 Phase 3 (3/3)).
        case canvas(CanvasSettingsFeature)
        /// 위젯에 표시할 말씀(시안 N7 · N8).
        case widget(WidgetSettingsFeature)
        /// 필사 사용법과 첫 안내 다시 보기.
        case help(HelpFeature)
        /// 앱 업데이트 변경 사항.
        case patchnote(PatchnoteFeature)
        case sendFeedback(SendFeedbackFeature)
        case appVersion(AppVersionFeature)
        /// 광고 제거 구매 · 복원(시안 K4).
        case removeAds(RemoveAdsFeature)
    }
    
    @Dependency(\.adConsentClient) var adConsentClient
    @Dependency(\.legacySeparationHoldState) var holdState

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                state.isPrivacyOptionsRequired = MainActor.assumeIsolated {
                    adConsentClient.isPrivacyOptionsRequired
                }
                state.isConnectionHeld = holdState.isHeld
            case .view(.privacyOptionsTapped):
                return .run { _ in
                    // 폼을 닫거나 띄우지 못해도 설정 화면 상태는 바뀌지 않는다.
                    try? await adConsentClient.presentPrivacyOptions()
                }
            case .push(let path):
                state.path = path
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
