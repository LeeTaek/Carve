//
//  AppCoordinatorView.swift
//  Carve
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveFeature
import ChartFeature
import SettingsFeature
import SwiftUI
import UIComponents

import ComposableArchitecture

/// AppCoordinatorFeature와 연결된 루트 코디네이터 View.
/// - Note: RootView는 트리 기반 네비게이션으로,
///  Settings / Charts(예정) 은 Stack 기반 네비게이션으로 구현.
public struct AppCoordinatorView: View {
    @Bindable private var store: StoreOf<AppCoordinatorFeature>
    
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
                ProgressView("필기를 보존하고 iCloud 연결을 준비하고 있어요")
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
        .allowsHitTesting(store.patchnote == nil && store.settings == nil && store.reconnectRequestID == nil)
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
        .disabled(store.reconnectRequestID != nil)
        .overlay {
            if store.reconnectRequestID != nil || store.reconnectError != nil {
                VStack(spacing: 16) {
                    if let message = store.reconnectError {
                        Text("연결 준비를 마치지 못했어요")
                        Text(message).font(.caption)
                        Button("확인") { store.send(.cancelReconnect) }
                    } else {
                        ProgressView("마지막 필기를 보존하고 있어요")
                        Button("취소") { store.send(.cancelReconnect) }
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if store.showsRelaunchGuidance {
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

    }
}
