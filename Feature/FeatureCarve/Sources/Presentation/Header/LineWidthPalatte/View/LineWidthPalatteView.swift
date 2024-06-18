//
//  LineWidthPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct LineWidthPalatteView: View {
    private var store: StoreOf<LineWidthPalatteReducer>
    public init(store: StoreOf<LineWidthPalatteReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Circle()
            .foregroundStyle(.red)
            .frame(width: 300, height: 200)
    }
}
