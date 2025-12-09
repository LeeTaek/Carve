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
                                    .locale(Locale(identifier: "ko_KR"))
                                    .month(.defaultDigits)
                                    .day(.defaultDigits)
                                    .weekday(.abbreviated)
                            ))
                        }
                    }

                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                }
            }
            .chartXScale(
                  domain: store.lowerBoundDate
                  ...
                  Calendar.current.startOfDay(for: Date())
              )
            .chartScrollableAxes(.horizontal)               // 가로 스크롤 활성화
            .chartXVisibleDomain(length: 86400 * 7)         // 한 페이지에 7일
            .chartScrollPosition(x: $store.scrollPosition)  // 현재 페이지 기준 값
            .chartScrollTargetBehavior(
              .valueAligned(
                matching: DateComponents(hour: 0),          // 하루 단위 스냅
                majorAlignment: .page                       // 페이지 단위로 스냅
              )
            )
            .chartXSelection(value: $store.selectedDate)
            .chartYScale(domain: 0...max(1, store.dailyRecords.map(\.count).max() ?? 0))
            .frame(height: UIScreen.main.bounds.height / 3)
        } else {
            EmptyView()
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
