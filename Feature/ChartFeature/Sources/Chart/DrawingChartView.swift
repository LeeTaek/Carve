//
//  DrawingChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: DrawingChartFeature.self)
public struct DrawingChartView: View {
    @Bindable public var store: StoreOf<DrawingChartFeature>
    
    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        Text("DrawingChartView")
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { DrawingChartFeature() }
    )
    DrawingChartView(store: store)
}
