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
        List {
            Section {
                DailyRecordChartView(
                    store: store.scope(
                        state: \.dailyRecordChart,
                        action: \.dailyRecordChart
                    )
                )
                // 섹션 헤더에는 영향 주지 않고, 콘텐츠(행)만 카드처럼 보이도록 처리
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .sectionCardShadow()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("주간 필사량")
                    .font(.subheadline)
                    .foregroundStyle(Color.Brand.ink)
            }
            
            Section {
                latestDrawingHistoryList
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .sectionCardShadow()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("최근 필사 내역")
                    .font(.subheadline)
                    .foregroundStyle(Color.Brand.ink)
            }
            
        }
        .scrollDisabled(store.dailyRecordChart.isScrolling)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
    
    private var latestDrawingHistoryList: some View {
        VStack {
            let totalCount = store.dailyRecordChart.records.reduce(0) { $0 + $1.count }
            Text("한 주 동안 \(totalCount)개의 절을 필사하셨네요!")
                .font(.subheadline)
                .padding()
            
            
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
