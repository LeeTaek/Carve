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
    @State private var isInteractingWithChart = false
    
    private let darkBlue = Color(hex: 0x0A77AE)
    private let lightBlue = Color(hex: 0x76DAF0)
    private let mediumBlue = Color(hex: 0x318FA8)
    private let primaryBlue = Color(hex: 0x089CF5)
    private let offWhite = Color(hex: 0xEBE8EB)
    private let darkGray = Color(hex: 0x343434)
    private let lavenderBlue = Color(hex: 0xC0BCE2)
    
    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        List {
            Section {
                DailyRecordChartView(
                    records: store.dailyRecords,
                    scrollPosition: $store.scrollPosition,
                    selectedDate: $store.selectedDate,
                    lowerBoundDate: store.lowerBoundDate
                )
            } header: {
                Text("주간 필사량")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            
            Section {
                latestDrawingHistoryList
            } header: {
                Text("최근 필사 내역")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            
        }
        .scrollDisabled(isInteractingWithChart)
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
            let totalCount = store.dailyRecords.reduce(0) { $0 + $1.count }
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
