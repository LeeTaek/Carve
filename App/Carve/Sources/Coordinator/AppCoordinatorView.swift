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
    @Bindable private var store: StoreOf<AppCoordinator>
    
    public init(store: StoreOf<AppCoordinator>) {
        self.store = store
    }
    
    public var body: some View {
        switch store.path {
        case .carve:
            if let store = store.scope(state: \.path?.carve, action: \.path.carve) {
                CarveNavigationView(store: store)
            }
        case .settings:
            if let store = store.scope(state: \.path?.settings, action: \.path.settings) {
                SettingsView(store: store)
            }
        default:
            fatalError("Store init Failed")
        }
    }
}
