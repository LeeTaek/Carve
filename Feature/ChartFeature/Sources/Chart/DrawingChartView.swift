//
//  DrawingChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI
import CarveToolkit

import ComposableArchitecture

@ViewAction(for: DrawingChartFeature.self)
public struct DrawingChartView: View {
    @Bindable public var store: StoreOf<DrawingChartFeature>

    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CardSection(title: "주간 필사량") {
                    DailyRecordChartView(
                        store: store.scope(
                            state: \.dailyRecordChart,
                            action: \.dailyRecordChart
                        )
                    )
                }

                DrawingWeeklySummaryView(
                    store: store.scope(
                        state: \.drawingWeeklySummary,
                        action: \.drawingWeeklySummary
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDisabled(store.dailyRecordChart.isScrolling)
        .background(Color.Brand.background)
        .navigationTitle("차트")
        .task {
            send(.fetchData)
        }
    }
}
