//
//  AppCoordinatorView.swift
//  Carve
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import FeatureCarve
import FeatureSettings
import SwiftUI

import ComposableArchitecture

public struct AppCoordinatorView: View {
    private var store: StoreOf<AppCoordinator>
    
    public init(store: StoreOf<AppCoordinator>) {
        self.store = store
    }
    
    public var body: some View {
        switch store.state {
        case .carve:
            if let store = store.scope(state: \.carve, action: \.carve) {
                CarveView(store: store)
            }
        case .settings:
            if let store = store.scope(state: \.settings, action: \.settings) {
                SettingsView(store: store)
            }
        }
    }
}
