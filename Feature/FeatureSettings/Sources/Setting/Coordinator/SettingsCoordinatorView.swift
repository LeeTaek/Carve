//
//  SettingsCoordinatorView.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import TCACoordinators

public struct SettingsCoordinatorView: View {
    private var store: StoreOf<SettingsCoordinator>
    
    public init(store: StoreOf<SettingsCoordinator>) {
        self.store = store
    }
    
    public var body: some View {
        TCARouter(store.scope(state: \.routes, action: \.router)) { screen in
            switch screen.case {
            case let .settings(store):
                SettingsView(store: store)
            case let .icloud(store):
                CloudSettingView(store: store)
            }
        }
    }
}
