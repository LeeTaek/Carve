//
//  App.swift
//  Carve
//
//  Created by 이택성 on 1/22/24.
//

import Domain
import SwiftData
import SwiftUI

import ComposableArchitecture
import Firebase
import FeatureCarve

@main
struct CarveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    public let store: StoreOf<AppCoordinator>
    private var launchStore = Store(initialState: .initialState) {
        LaunchProgressReducer()
    }
    @StateObject private var cloudKitContainer = PersistentCloudKitContainer.shared
    
    init() {
        self.store = Store(initialState: .initialState) {
            AppCoordinator()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if launchStore.launchState == .completed {
                    AppCoordinatorView(store: store)
                        .analyticsScreen(
                            name: "Screen Name",
                            extraParameters: [
                                AnalyticsParameterScreenName: "\(type(of: self))",
                                AnalyticsParameterScreenClass: "\(type(of: self))"
                            ]
                        )
                } else {
                    LaunchProgressView(store: launchStore)
                }
            }
        }
        .modelContainer(cloudKitContainer.container)
    }
}
