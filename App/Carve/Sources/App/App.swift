//
//  App.swift
//  Carve
//
//  Created by 이택성 on 1/22/24.
//


import SwiftUI

import ComposableArchitecture
import Firebase
import RealmSwift
import FeatureCarve

@main
struct CarveApp: SwiftUI.App {
    let realmApp = RealmSwift.App(id: "application-0-xqvkw")
    
    var body: some Scene {
        @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
        let store = Store(initialState: .initialState) {
            CarveReducer()
        }
        
        WindowGroup {
            WithPerceptionTracking {
                CarveView(store: store)
                    .analyticsScreen(
                        name: "Screen Name",
                        extraParameters: [
                            AnalyticsParameterScreenName: "\(type(of: self))",
                            AnalyticsParameterScreenClass: "\(type(of: self))"
                        ]
                    )
            }
        }
    }
}
