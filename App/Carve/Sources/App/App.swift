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
    public var modelContainer: ModelContainer
    public let store: StoreOf<AppCoordinator>
    
    init() {
        self.modelContainer = {
            @Dependency(\.databaseService) var databaseService
            do {
                let modelContainer = try databaseService.container()
                return modelContainer
            } catch {
                fatalError("Could not find modelcontext")
            }
        }()
        self.store = Store(initialState: .initialState) {
            AppCoordinator()
        }
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
        .modelContainer(self.modelContainer)
    }
    
}
