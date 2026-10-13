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
    /// 화면 언어 — 앱 안에서 언어를 고르면 앱 루트가 바꾼다. 빈 상태 컴포넌트에 넘기는 문구는 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

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
        .navigationTitle(Text("차트", bundle: .module, comment: "차트 화면 제목"))
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
            ChartCatalog.string("아직 기록이 없어요", locale: locale),
            message: ChartCatalog.string("한 절이라도 필사하면 여기에 쌓여요.", locale: locale),
            actionTitle: ChartCatalog.string("필사하러 가기", locale: locale)
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
