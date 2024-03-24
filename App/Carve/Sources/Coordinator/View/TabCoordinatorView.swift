//
//  TabCoordinatorView.swift
//  Carve
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import FeatureCarve
import FeatureSettings

import ComposableArchitecture
import TCACoordinators

struct TabCoordinatorView: View {
    let store: StoreOf<TabCoordinator>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            TabView(selection: viewStore.$currentActiveTab) {
                CarveCoordinatorView(
                    store: store.scope(
                        state: \.carve,
                        action: \.carve
                    )
                )
                .tabItem {
                    Image(viewStore.tabBarContents[0].image)
                    Text(viewStore.tabBarContents[0].name)
                }
                .toolbar(viewStore.isHidden, for: .tabBar)
                .animation(.easeInOut(duration: 0.3), value: viewStore.isHidden)
                .tag(viewStore.tabBarContents[0].tag)
                
                SettingsCoordinatorView(
                    store: store.scope(
                        state: \.settings,
                        action: \.settings
                    )
                )
                .tabItem {
                    Image(viewStore.tabBarContents[1].image)
                    Text(viewStore.tabBarContents[1].name)
                }
                .tag(viewStore.tabBarContents[1].tag)
            }
            .tint(.pink)
        }
    }
}
