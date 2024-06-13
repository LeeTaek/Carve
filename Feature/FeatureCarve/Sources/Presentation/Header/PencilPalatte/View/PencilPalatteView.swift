//
//  PencilPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct PencilPalatteView: View {
    private var store: StoreOf<PencilPalatteReducer>
    public init(store: StoreOf<PencilPalatteReducer>) {
        self.store = store
    }
   
    public var body: some View {
        Text("PencilSettingsView")
    }
}
