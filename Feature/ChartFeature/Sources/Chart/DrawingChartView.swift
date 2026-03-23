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
#if DEBUG
import Domain
import PencilKit
#endif

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

                // 상단: 차트 카드(가로 전체)
                CardSection(title: "주간 필사량") {
                    DailyRecordChartView(
                        store: store.scope(
                            state: \.dailyRecordChart,
                            action: \.dailyRecordChart
                        )
                    )
                }

                // 하단: 타일 3개 (가로 여유에 따라 3열/2열/1열로 자동 개행)
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
        // 차트 드래그 중에는 바깥 스크롤을 잠가서 gesture 충돌을 줄임
        .scrollDisabled(store.dailyRecordChart.isScrolling)
        .background(Color.Brand.background)
        .task {
#if DEBUG
            // Xcode 프리뷰에서는 fetchData 안 날림
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                send(.fetchData)
            }
#else
            send(.fetchData)
#endif
        }
    }
}


#Preview {
    @Previewable @State var store = Store(initialState: .previewState) {
        DrawingChartFeature()
    } withDependencies: { dependency in
        dependency.drawingData = .previewValue
    }
    
    DrawingChartView(store: store)
}
