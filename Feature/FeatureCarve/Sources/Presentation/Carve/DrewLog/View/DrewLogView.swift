//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI
import Resources

import ComposableArchitecture

public struct DrewLogView: View {
    @Bindable private var store: StoreOf<DrewLogReducer>
    
    public init(store: StoreOf<DrewLogReducer>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }

    
    public var content: some View {
        VStack {
            Button(action: { store.send(.view(.dismiss)) }) {
                Text("DrewLogView")
                    .font(Font(ResourcesFontFamily.NanumGothic.bold
                        .font(size: 30)))
                    .foregroundStyle(.black.opacity(0.7))
                    .padding()
            }
            
            Chart(store.chartData) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Count", entry.count)
                )
            }
            .onAppear {
                store.send(.inner(.fetchChartData))
            }
        }
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { DrewLogReducer() },
        withDependencies: {
            $0.drawingData = .previewValue
        }
    )
//    store.send(.inner(.setPreviewValue))
    return DrewLogView(store: store)
}
