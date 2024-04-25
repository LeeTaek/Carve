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
struct CarveApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    public var modelContext: ModelContext
    public let store: Store<CarveReducer.State, CarveReducer.Action>
    
    init() {
        self.modelContext = {
            @Dependency(\.databaseService) var databaseService
            guard let modelContext = try? databaseService.context() else {
                fatalError("Could not find modelcontext")
            }
            return modelContext
        }()
        self.store = Store(initialState: .initialState) {
            CarveReducer()
        }
    }
    
    
    var body: some Scene {
        WindowGroup {
            CarveView(store: store)
                .analyticsScreen(
                    name: "Screen Name",
                    extraParameters: [
                        AnalyticsParameterScreenName: "\(type(of: self))",
                        AnalyticsParameterScreenClass: "\(type(of: self))"
                    ]
                )
        }
        .modelContext(self.modelContext)
    }
    
}
