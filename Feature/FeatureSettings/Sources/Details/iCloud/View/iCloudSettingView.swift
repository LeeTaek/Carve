//
//  iCloudSettingView.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct CloudSettingView: View {
    private var store: StoreOf<CloudSettingsReducer>
    
    public init(store: StoreOf<CloudSettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Text("iCloud")
    }
}
