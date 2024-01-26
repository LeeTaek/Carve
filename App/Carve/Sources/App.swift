//
//  App.swift
//  Carve
//
//  Created by 이택성 on 1/22/24.
//


import SwiftUI
import ComposableArchitecture
import Feature

@main
struct CarveView: App {
    var body: some Scene {
        WindowGroup {
            CarveMainView(
                store: Store(initialState: CarveReducer.State()) {
                    CarveReducer()
                        ._printChanges()
                }
            )
        }
    }
}
