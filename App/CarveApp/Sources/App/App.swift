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
import CarveFeature
import FirebaseAnalytics

@main
struct CarveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private var store: StoreOf<AppCoordinatorFeature>
    var modelContainer: ModelContainer
    
    init() {
        let containerID = Self.makeContainerID()
        let modelContainer = Self.makeModelContainer(containerID: containerID)
        self.modelContainer = modelContainer
        self.store = Self.makeStore(containerID: containerID, modelContainer: modelContainer)
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
    private static func makeContainerID() -> ContainerID {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String ?? ""
        return ContainerID(id: id)
    }

    private static func makeModelContainer(containerID: ContainerID) -> ModelContainer {
        withDependencies {
            $0.containerId = containerID
        } operation: {
            DependencyValues._current.modelContainer
        }
    }

    private static func makeStore(containerID: ContainerID, modelContainer: ModelContainer) -> StoreOf<AppCoordinatorFeature> {
        withDependencies {
            $0.containerId = containerID
            $0.modelContainer = modelContainer
        } operation: {
            Store(initialState: .initialState) {
                AppCoordinatorFeature()
            }
        }
    }
}
