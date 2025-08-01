//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct DrewLogView: View {
    @Bindable private var store: StoreOf<DrewLogFeature>
    
    public init(store: StoreOf<DrewLogFeature>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }
    
    public var content: some View {
        Text("Hello, World!")
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { DrewLogFeature() }
    )
    DrewLogView(store: store)
}
