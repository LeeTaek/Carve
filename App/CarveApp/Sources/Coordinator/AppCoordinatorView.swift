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
