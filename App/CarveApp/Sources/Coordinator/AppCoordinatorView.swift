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
                fatalError("RootView init failed")
            }
        } destination: { store in
            // push destination - Stack 기반
            switch store.case {
            case .settings(let store):
                SettingsView(store: store)
                
            case .chart(let store):
                DrawingChartView(store: store)
            }
        }
    }
}
