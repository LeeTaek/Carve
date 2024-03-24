//
//  SettingsCoordinatorView.swift
//  Settings
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import TCACoordinators

public struct SettingsCoordinatorView: View {
    let store: StoreOf<SettingsCoordinator>

    public init(store: StoreOf<SettingsCoordinator>) {
        self.store = store
    }

    public var body: some View {
        TCARouter(store) { screen in
            SwitchStore(screen) { screen in
                switch screen {
                case .carve:
                    CaseLet(
                        /SettingsScreen.State.carve,
                         action: SettingsScreen.Action.carve,
                         then: SettingsView.init
                    )
                }
            }
        }
    }
}
