//
//  DrawingChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents

import ComposableArchitecture

@ViewAction(for: DrawingChartFeature.self)
public struct DrawingChartView: View {
    @Bindable public var store: StoreOf<DrawingChartFeature>

    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            Group {
                if store.dailyRecordChart.hasWrittenRecord {
                    chartContent
                } else {
                    emptyContent
                }
            }
            .padding(.horizontal, CarveSpacing.xLarge)
            .padding(.vertical, CarveSpacing.large)
        }
        .scrollDisabled(store.dailyRecordChart.isScrolling)
        .background(CarveColor.canvas)
        .navigationTitle("차트")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            send(.fetchData)
        }
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.large) {
            DailyRecordChartView(
                store: store.scope(
                    state: \.dailyRecordChart,
                    action: \.dailyRecordChart
                )
            )

            DrawingWeeklySummaryView(
                store: store.scope(
                    state: \.drawingWeeklySummary,
                    action: \.drawingWeeklySummary
                )
            )
        }
    }

    private var emptyContent: some View {
        CarveEmptyState(
            "아직 기록이 없어요",
            message: "한 절이라도 필사하면 여기에 쌓여요.",
            actionTitle: "필사하러 가기"
        ) {
            send(.backToWriting)
        }
        .frame(maxWidth: 480, minHeight: 280)
        .carveSurface(
            .panel,
            in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous)
        )
        .frame(maxWidth: .infinity)
        .padding(.top, CarveSpacing.xSmall)
    }
}
