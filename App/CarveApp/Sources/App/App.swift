//
//  App.swift
//  Carve
//
//  Created by 이택성 on 1/22/24.
//

import Data
import SwiftData
import SwiftUI

import ComposableArchitecture
import CarveFeature
import FirebaseAnalytics

@main
struct CarveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private var store: StoreOf<AppCoordinatorFeature>
    @Dependency(\.modelContainer) var modelContainer: ModelContainer
    
    init() {
        self.store = Self.makeStore()
    }
    
    var body: some Scene {
        WindowGroup {
            AppCoordinatorView(store: store)
                .analyticsScreen(
                    name: "Screen Name",
                    extraParameters: [
                        AnalyticsParameterScreenName: "\(type(of: self))",
                        AnalyticsParameterScreenClass: "\(type(of: self))"
                    ]
                )
            
        }
        .modelContainer(modelContainer)
    }
}


// MARK: - helpers
extension CarveApp {
    private static func makeStore() -> StoreOf<AppCoordinatorFeature> {
        withDependencies(AppDependencies.configure()) {
            Store(initialState: .initialState) {
                AppCoordinatorFeature()
            }
        }
    }
}
