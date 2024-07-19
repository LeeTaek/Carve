//
//  AppVersionView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct AppVersionView: View {
    private var store: StoreOf<AppVersionReducer>
    
    public init(store: StoreOf<AppVersionReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Text("AppVersion")
    }
}
