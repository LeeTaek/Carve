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

public struct AppCoordinatorView: View {
    @Bindable private var store: StoreOf<AppCoordinatorFeature>
    
    public init(store: StoreOf<AppCoordinatorFeature>) {
        self.store = store
    }
    
    public var body: some View {
        switch store.path {
        case .launchProgress:
            if let store = store.scope(state: \.path?.launchProgress,
                                       action: \.path.launchProgress) {
                LaunchProgressView(store: store)
            }
        case .carve:
            if let store = store.scope(state: \.path?.carve, action: \.path.carve) {
                CarveNavigationView(store: store)
            }
        case .settings:
            if let store = store.scope(state: \.path?.settings, action: \.path.settings) {
                SettingsView(store: store)
            }
        case .chart:
            if let store = store.scope(state: \.path?.chart, action: \.path.chart) {
                DrawingChartView(store: store)
            }
        default:
            fatalError("Store init Failed")
        }
    }
}
