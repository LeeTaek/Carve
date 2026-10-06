//
//  AppCoordinatorView.swift
//  Carve
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveFeature
import ChartFeature
import ClientInterfaces
import SettingsFeature
import SwiftUI
import UIComponents

import ComposableArchitecture

/// AppCoordinatorFeature와 연결된 루트 코디네이터 View.
/// - Note: RootView는 트리 기반 네비게이션으로,
///  Settings / Charts(예정) 은 Stack 기반 네비게이션으로 구현.
public struct AppCoordinatorView: View {
    @Bindable private var store: StoreOf<AppCoordinatorFeature>
    /// 설정 > 화면 모드에서 고른 값. 설정 화면이 쓰고 여기서는 읽기만 한다.
    @SharedReader(.appearanceMode) private var appearanceMode: AppearanceMode
    
    public init(store: StoreOf<AppCoordinatorFeature>) {
        self.store = store
    }
    
    /// TCA Path 상태에 따라 Launch/Carve/Settings 중 하나의 화면을 선택적으로 렌더링.
    public var body: some View {
        NavigationStack(
          path: $store.scope(state: \.path, action: \.path)
        ) {
            // RootView 설정 - Tree 기반
            switch store.root {
            case .launchProgress:
                if let store = store.scope(
                    state: \.root?.launchProgress,
                    action: \.root.launchProgress
                ) {
                    LaunchProgressView(store: store)
                }
            case .carve:
                if let store = store.scope(
                    state: \.root?.carve,
                    action: \.root.carve
                ) {
                    CarveNavigationView(store: store)
                }
            default:
                fatalError("RootView init failed")
            }
        } destination: { store in
            // push destination - Stack 기반
            switch store.case {
            case .chart(let store):
                DrawingChartView(store: store)
            case .favorites(let store):
                FavoriteListView(store: store)
            }
        }
        .allowsHitTesting(store.patchnote == nil && store.settings == nil)
        .accessibilityHidden(store.patchnote != nil || store.settings != nil)
        .overlay {
            if let settingsStore = store.scope(state: \.settings, action: \.settings.presented) {
                ZStack {
                    CarveColor.scrim
                        .ignoresSafeArea()
                    SettingsView(store: settingsStore)
                        .padding(60)
                }
            }
        }
        .overlay {
            if let patchnoteStore = store.scope(state: \.patchnote, action: \.patchnote.presented) {
                PatchnoteView(store: patchnoteStore)
            }
        }
        .overlay {
            if store.showsRelaunchGuidance {
                // 로그인 완료와 연결 완료를 구분한다 — 이 실행은 계속 이 기기에만 저장한다. 기다릴 것이 없으므로 로딩을 띄우지 않는다.
                VStack(spacing: 16) {
                    Text("iCloud 로그인을 확인했어요")
                    Text("아직 이 기기의 필사는 iCloud와 연결되지 않았어요.\n\(CloudSettingsFeature.relaunchToConnect)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("확인") { store.send(.relaunchGuidanceDismissed) }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("relaunchGuidance")
            }
        }
        .overlay {
            // 연결 전에 쓴 필기가 있다 — 막지 않고 한 번 알린다. 넣기는 설정에서 절마다 견주고 고른 것만 한다(2026-09-29).
            if store.beforeConnectionNotice != nil, store.patchnote == nil, store.settings == nil, !store.showsRelaunchGuidance {
                VStack(spacing: 16) {
                    Text("iCloud에 연결하기 전에 이 iPad에서 쓴 필기가 있어요")
                    Text("현재 필사에 넣을 내용을 확인해 주세요.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("나중에") { store.send(.beforeConnectionNoticeDismissed) }
                        Button("필기 확인하기") { store.send(.beforeConnectionNoticeReviewTapped) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("beforeConnectionNotice")
            }
        }
        .overlay {
            // 2.0.x 에서 절마다 쓰는 캔버스로 쓰던 사용자 — 그 캔버스가 없어졌다고 막지 않고 한 번 알린다(2.1 결정 6).
            // 연결 전 필기 안내와 같은 규칙으로 미루고, 두 카드가 겹치지 않게 연결 전 필기 안내가 떠 있는 동안에도 미룬다.
            if store.showsCanvasRemovalNotice, store.patchnote == nil, store.settings == nil, !store.showsRelaunchGuidance,
               store.beforeConnectionNotice == nil {
                VStack(spacing: 16) {
                    Text("절마다 쓰는 캔버스는 이번 버전에서 없어졌어요")
                    Text("그동안 쓴 필사는 그대로예요. 불편한 점이 있으면 알려 주세요.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("의견 보내기") { store.send(.canvasRemovalNoticeFeedbackTapped) }
                        Button("확인") { store.send(.canvasRemovalNoticeDismissed) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvasRemovalNotice")
            }
        }
        // 이 창의 오버레이 · 팝오버까지 같은 모드를 따른다. 필사 영역은 모드와 무관하게 라이트로 그린다(결정 8-1 안 1).
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}

private extension AppearanceMode {
    /// `nil` 이면 기기의 라이트 · 다크 설정을 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
