//
//  DailyRecordChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 12/15/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import Charts
import CarveToolkit

import ComposableArchitecture

/// 하루 단위 필사량을 주간 단위로 페이징하여 보여주는 차트.
/// 페이징 스크롤이 원하는대로 구현이 안되서 무한 스크롤 아이디어 차용(MeasurementChartView 참고),
/// 뒤에 축을 표시한 Chart위에 페이징용 스크롤 덮어서 구현
@ViewAction(for: DailyRecordChartFeature.self)
struct DailyRecordChartView: View {
    @Bindable var store: StoreOf<DailyRecordChartFeature>
    private let pageDays: Int = DailyRecordChartFeature.pageDays
    
    private let background = Color.Brand.background
    private let secondary = Color.Brand.secondary
    
    private let visiblePageIndex = 1
    
    
    var body: some View {
        if store.records.isEmpty {
            Text("최근 한 달 동안의 필사 기록이 없어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height / 3)
        } else {
            GeometryReader { geo in
                ZStack {
                    // Background chart: 축/그리드만 담당 (터치 비활성)
                    axisChart
                        .allowsHitTesting(false)
                        .frame(width: geo.size.width)
                    
                    // Foreground chart: 실제 데이터 + 페이징
                    pager
                        .frame(width: geo.size.width, alignment: .leading)
                }
                .padding(.vertical, 12)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .onAppear {
                    send(.onAppear(width: geo.size.width))
                }
                .onChange(of: geo.size.width) { _, newValue in
                    send(.widthChanged(newValue))
                }
            }
            .frame(height: UIScreen.main.bounds.height / 3)
        }
    }
    
    /// X축에 반드시 표시할 날짜 목록(현재 페이지 기준으로 pageDays개)
    private func xAxisDates(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? store.scrollPosition.alignToDay()
        return (0..<pageDays).map { start.addDays($0).middleOfDay() }
    }
    
    /// X축 그리드/틱(세로 점선)은 날짜 경계(00:00)에 둠. (pageDays+1개)
    private func xAxisBoundaries(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? store.scrollPosition.alignToDay()
        return (0...pageDays).map { start.addDays($0) }
    }
    
    /// 뒤에 축 그리는 배경 View
    private var axisChart: some View {
        let visible = store.pages[safe: visiblePageIndex]
        
        let start = store.scrollPosition.alignToDay()
        let endExclusive = start.addDays(pageDays)
        let fallbackXDomain = start...endExclusive
        
        return Chart {
        }
        .chartXScale(domain: visible?.xDomain ?? fallbackXDomain)
        .chartYScale(domain: store.yScale)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))")
                            .foregroundStyle(Color.Brand.ink)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisBoundaries(for: visible)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                AxisTick()
                // 라벨 영역은 유지
                AxisValueLabel {
                    Text(" ")
                        .font(.caption2)
                        .foregroundStyle(.clear)
                }
            }
        }
        /// 맨 마지막 라벨 잘리는 현상 있어서 직접 추가
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame: CGRect = {
                    if let anchor = proxy.plotFrame {
                        return geo[anchor]
                    } else {
                        return .zero
                    }
                }()
                let dates = xAxisDates(for: visible)
                
                ForEach(dates, id: \.self) { date in
                    if let xPosition = proxy.position(forX: date) {
                        // 라벨이 끝에서 잘리지 않도록 plot 영역 안쪽으로 clamp
                        let x = min(max(xPosition, plotFrame.minX + 22), plotFrame.maxX - 22)
                        
                        let md = date.formatted(
                            Date.FormatStyle()
                                .locale(Locale(identifier: "ko_KR"))
                                .month(.twoDigits)
                                .day(.twoDigits)
                        )
                        let wd = date.formatted(
                            Date.FormatStyle()
                                .locale(Locale(identifier: "ko_KR"))
                                .weekday(.narrow)
                        )
                        
                        Text("\(md) (\(wd))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.Brand.ink)
                        // X축 라벨 영역(플롯 하단 바로 아래)에 배치
                            .position(x: x, y: plotFrame.maxY + 12)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    /// 앞에 Paging Charts
    private var pager: some View {
        HStack(spacing: 0) {
            // 이전/현재/다음 페이지 (가운데만 selection 허용)
            pageChart(store.pages[safe: 0], allowsSelection: false)
                .frame(width: store.pageWidth)
            
            pageChart(store.pages[safe: 1], allowsSelection: true)
                .frame(width: store.pageWidth)
            
            pageChart(store.pages[safe: 2], allowsSelection: false)
                .frame(width: store.pageWidth)
        }
        .offset(x: (-store.pageWidth * CGFloat(visiblePageIndex)) + store.dragX)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    send(.dragChanged(translationX: value.translation.width))
                }
                .onEnded { value in
                    send(.dragEnded(translationX: value.translation.width))
                }
        )
        .clipped()
    }
    
    /// Chart
    private func pageChart(_ page: ChartPage?, allowsSelection: Bool) -> some View {
        let page = page
        
        let start = store.scrollPosition.alignToDay()
        let endExclusive = start.addDays(pageDays)
        let fallbackXDomain = start...endExclusive
        
        return Chart(page?.entries ?? []) { record in
            let isSelected = allowsSelection
            && store.selectedDate.map { Calendar.current.isDate(record.date, inSameDayAs: $0) } == true
            
            BarMark(
                x: .value("날짜", record.date.middleOfDay(), unit: .day),
                y: .value("필사량", record.count),
                width: .ratio(0.55)
            )
            .cornerRadius(6)
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [background, secondary]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .opacity(isSelected ? 1.0 : 0.65)
            .annotation(position: .top, alignment: .center) {
                if isSelected {
                    Text("\(record.count)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.Brand.secondary)
                        .clipShape(Capsule())
                } else {
                    Text("\(record.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel().foregroundStyle(.clear)
                
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisBoundaries(for: page)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel().foregroundStyle(.clear)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: page?.xDomain ?? fallbackXDomain)
        .chartYScale(domain: store.yScale)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard allowsSelection else { return }
                                
                                let plotFrame: CGRect = {
                                    if let anchor = proxy.plotFrame { return geo[anchor] }
                                    else { return .zero }
                                }()
                                
                                let x = value.location.x - plotFrame.minX
                                if let date: Date = proxy.value(atX: x) {
                                    store.selectedDate = Calendar.current.startOfDay(for: date)
                                }
                            }
                    )
            }
        }
    }
}


#Preview("Sample - 최근 30일") {
    DailyRecordChartPreview()
}

private struct DailyRecordChartPreview: View {
    private let store: StoreOf<DailyRecordChartFeature>
    
    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        // 최근 20일 더미 데이터
        let records: [DailyRecord] = (0..<31).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyRecord(date: date, count: Int.random(in: 3...15))
        }
            .sorted { $0.date < $1.date }
        
        
        let lowerBoundDate = cal.date(byAdding: .day, value: -30, to: today) ?? today
        let initialScroll = cal.date(byAdding: .day, value: -6, to: today) ?? today
        
        self.store = Store(
            initialState: DailyRecordChartFeature.State(
                records: records,
                lowerBoundDate: lowerBoundDate,
                scrollPosition: initialScroll,
                selectedDate: today
            )
        ) {
            DailyRecordChartFeature()
        }
    }
    
    var body: some View {
        DailyRecordChartView(store: store)
            .padding()
    }
}
