//
//  SentenceSettingsView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct SentenceSettingsView: View {
    private var store: StoreOf<SentenceSettingsReducer>
    public init(store: StoreOf<SentenceSettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Text("SentenceSettingsView")
        
    }
}
