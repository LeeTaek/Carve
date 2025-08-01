//
//  DrawingChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI
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
            Section{
                chart
            } header: {
                Text("주간 필사량")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }
    
    public var chart: some View {
        Chart {
            ForEach(store.dailyRecords, id: \.date) { record in
                BarMark(
                    x: .value("Date", record.date, unit: .day),
                    y: .value("필사량", record.count)
                )
                .cornerRadius(8)
                .foregroundStyle(Color.teal)
                .annotation(position: .top) {
                    Text("\(record.count)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(
                            Date.FormatStyle()
                                .locale(Locale(identifier: "ko_KR"))
                                .month(.defaultDigits)
                                .day(.defaultDigits)
                                .weekday(.abbreviated)
                        ))
                    }
                }
            }
        }
        .frame(height: 450)
        .onAppear {
            send(.fetchData)
        }
    }
}

#Preview {

    @Previewable @State var store = Store(initialState: .initialState) {
        DrawingChartFeature()
    } withDependencies: { dependency in
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: today)!
        
        let sampleDrawing = [
            BibleDrawing(bibleTitle: .initialState, section: 4, lineData: .mockDrawing, updateDate: yesterday),
            BibleDrawing(bibleTitle: .initialState, section: 5, lineData: .mockDrawing, updateDate: yesterday),
            BibleDrawing(bibleTitle: .initialState, section: 6, lineData: .mockDrawing, updateDate: dayBeforeYesterday)
        ]
        
        for drawing in sampleDrawing {
            try? dependency.createSwiftDataActor.insert(drawing)
        }
    }

    
    DrawingChartView(store: store)
}
