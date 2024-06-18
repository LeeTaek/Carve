//
//  ColorPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct ColorPalatteView: View {
    private var store: StoreOf<ColorPalatteReducer>
    public init(store: StoreOf<ColorPalatteReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Rectangle()
            .foregroundStyle(.cyan)
            .frame(width: 200, height: 100)
    }
}
