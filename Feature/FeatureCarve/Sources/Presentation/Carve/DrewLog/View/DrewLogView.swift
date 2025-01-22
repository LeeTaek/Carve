//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Charts
import SwiftUI

import ComposableArchitecture

public struct DrewLogView: View {
    @Bindable private var store: StoreOf<DrewLogReducer>
    @State private var isAnimating: Bool = false
    @State private var textAnimating: Bool = false

    public init(store: StoreOf<DrewLogReducer>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }
    
    private var content: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                title
                List {
                    Section {
                        chart
                            .frame(
                                width: (geometry.size.width/9) * 8,
                                height: geometry.size.height/4,
                                alignment: .center
                            )
                    } header: {
                        chartTitle
                    }
                    Section {
                        carvingTrackerChart
                    } header: {
                        carvingTrackerChartTitle
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    
    private var title: some View {
        Button(action: { store.send(.view(.dismiss)) }) {
            Text("필사 기록")
                .navigationTitleStyle()
        }
        .padding()
        
    }
    
    private var chartTitle: some View {
        HStack {
            if store.chartData.isEmpty {
                Text("지난 한 주 필사 내역이 없어요.")
                    .sublineStyle(size: 18, opacity: 0.7)
            } else {
                Text("지난 한 주")
                    .sublineStyle(size: 18, opacity: 0.7)
                Text("\(store.totalSection)")
                    .sublineStyle(size: 25)
                
                Text("절의 말씀을 새겼네요.")
                    .sublineStyle(size: 18, opacity: 0.7)
                
            }
        }
    }
    
    private var chart: some View {
        GeometryReader { geometry in
            Chart(store.chartData) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Count", isAnimating ? entry.count : 0)
                )
                .annotation(position: .top, alignment: .center) {
                    Text("\(entry.count)절")
                        .fixedSize()
                        .sublineStyle(size: 12, opacity: textAnimating ? 0.7: 0)
                        .animation(.easeInOut(duration: 1.0), value: textAnimating)
                }
                .cornerRadius(10)
                .foregroundStyle(by: .value("Date", entry.date))
            }
            .chartYScale(domain: 0...store.maxY)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: store.chartData.map { $0.date }) {
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                    AxisGridLine()
                }
            }
            .padding()
        }
        .task {
            store.send(.inner(.fetchChartData))
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeInOut(duration: 1.0)) {
                self.isAnimating = true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.easeInOut(duration: 10.0)) {
                self.textAnimating = true
            }
        }
    }
    
    
    private var carvingTrackerChartTitle: some View {
        HStack {
            Text("필사 현황")
                .sublineStyle(size: 18, opacity: 0.7)
        }
    }
    private var carvingTrackerChart: some View {
        Text("성경 필사 표 ")
    }
    
    private func calculateDomainRange(from dates: [Date]) -> ClosedRange<Date> {
        print(dates)
        let startDate = dates.first ?? Date().toLocalTime()
        let endDate = dates.last ?? Date().toLocalTime()
        return startDate...endDate
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
    return DrewLogView(store: store)
}
