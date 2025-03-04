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
    @StateObject private var cloudKitContainer = PersistentCloudKitContainer.shared
    @State private var isDataLoaded: Bool = false
    
    init() {
        self.store = Store(initialState: .initialState) {
            AppCoordinator()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isDataLoaded {
                    AppCoordinatorView(store: store)
                        .analyticsScreen(
                            name: "Screen Name",
                            extraParameters: [
                                AnalyticsParameterScreenName: "\(type(of: self))",
                                AnalyticsParameterScreenClass: "\(type(of: self))"
                            ]
                        )
                } else {
                    LaunchProgressView()
                }
            }
            .onChange(of: cloudKitContainer.progress) {
                checkDataLoaded()
            }
            .onChange(of: cloudKitContainer.syncState) {
                checkDataLoaded()
            }
        }
        .modelContainer(cloudKitContainer.container)
    }
    
    private func checkDataLoaded() {
        if (cloudKitContainer.progress >= 1.0 && cloudKitContainer.syncState == .success)
            || cloudKitContainer.syncState == .next {
            withAnimation {
                isDataLoaded = true
            }
        }
    }
}
