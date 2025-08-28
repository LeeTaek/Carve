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
                chart()
            } header: {
                Text("주간 필사량")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
        .task {
            send(.fetchData)
        }
    }
    
    @ViewBuilder
    public func chart() -> some View {
        if (store.dailyRecords.last?.date) != nil {
            Chart(store.dailyRecords) { record in
                LineMark(
                    x: .value("날짜", record.date, unit: .day),
                    y: .value("필사량", record.count)
                )
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [lightBlue, primaryBlue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .symbol {
                    if let count = store.selectedRecord?.count,
                       let id = store.selectedRecord?.id {
                        CustomSymbol(value: count, isSelected: id == record.id)
                    } else {
                        EmptyView()
                    }
                }
                .interpolationMethod(.cardinal(tension: 0.4))
            }
            .chartXAxis {           // X축 UI
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {        // x축 라벨
                        if let date = value.as(Date.self) {
                            Text(date.formatted(
                                Date.FormatStyle()
                                    .
                                locale(Locale(identifier: "ko_KR"))
                                    .month(.defaultDigits)
                                    .day(.defaultDigits)
                                    .weekday(.abbreviated)
                            ))
                        }
                    }

                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                }
            }
            .chartXVisibleDomain(length: 86400 * 7)  // 7일
            .chartScrollPosition(x: $store.scrollPosition)
            .chartScrollableAxes(.horizontal)
            .chartXSelection(value: $store.selectedDate)
            .chartYScale(domain: 0...max(1, store.dailyRecords.map(\.count).max() ?? 0))
            .chartScrollTargetBehavior(
              .valueAligned(
                matching: DateComponents(hour: 0),               // 스냅 기준: 매일 00:00
                majorAlignment: .page
              )
            )
            .frame(height: UIScreen.main.bounds.height / 3)
        } else {
            EmptyView()
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
