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
import UIComponents

import ComposableArchitecture

@ViewAction(for: DailyRecordChartFeature.self)
struct DailyRecordChartView: View {
    @Bindable var store: StoreOf<DailyRecordChartFeature>
    /// 화면 언어 — 앱 안에서 언어를 고르면 앱 루트가 바꾼다. 미리 만드는 문구(카드 제목 · 날짜 · 접근성 문장)는 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale
    private let pageDays: Int = DailyRecordChartFeature.pageDays
    private let visiblePageIndex = 1
    
    var body: some View {
        VStack(spacing: CarveSpacing.medium) {
            weekNavigator

            CardSection(title: ChartCatalog.string("하루에 필사한 절", locale: locale)) {
                GeometryReader { geometry in
                    ZStack {
                        axisChart
                            .allowsHitTesting(false)
                            .frame(width: geometry.size.width)

                        pager
                            .frame(width: geometry.size.width, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        send(.onAppear(width: geometry.size.width))
                    }
                    .onChange(of: geometry.size.width) { _, newValue in
                        send(.widthChanged(newValue))
                    }
                }
                .frame(height: 236)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.state.accessibilitySummary(locale: locale))
            }
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: CarveSpacing.medium) {
            CarveIconButton(.chevronLeft, accessibilityLabel: ChartCatalog.string("이전 주", locale: locale)) {
                send(.previousWeekTapped)
            }
            .disabled(!store.canMoveToPreviousWeek)

            VStack(spacing: CarveSpacing.xxSmall) {
                // 날짜는 화면 언어(환경 locale) 서식이고 사이의 「 – 」 는 어느 언어든 같다 — 카탈로그를 거치지 않는다.
                Text(verbatim: "\(store.visibleStartDate.chartShortMonthDayText(locale: locale)) – \(store.visibleEndDate.chartShortMonthDayText(locale: locale))")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .monospacedDigit()

                relativeWeekText
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
            }
            .frame(maxWidth: 280)
            .accessibilityElement(children: .combine)

            CarveIconButton(.chevronRight, accessibilityLabel: ChartCatalog.string("다음 주", locale: locale)) {
                send(.nextWeekTapped)
            }
            .disabled(!store.canMoveToNextWeek)
        }
        .frame(maxWidth: .infinity)
    }

    /// 보이는 7일이 오늘에서 얼마나 떨어졌는지(「이번 주」 · 「지난 주」 · 「3주 전」). 키 기반 `Text` 라 환경 locale 을 그대로 따른다.
    private var relativeWeekText: Text {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: store.visibleEndDate)
        let days = calendar.dateComponents([.day], from: end, to: today).day ?? 0

        switch days {
        case ...0: return Text("이번 주", bundle: .module, comment: "차트 주 머리 — 보이는 7일이 오늘을 포함한다")
        case 1...7: return Text("지난 주", bundle: .module, comment: "차트 주 머리 — 보이는 7일이 바로 앞 주다")
        default:
            let weeks = max(1, Int(round(Double(days) / 7.0)))
            return Text("\(weeks)주 전", bundle: .module, comment: "차트 주 머리 — 보이는 7일이 N주 전이다")
        }
    }
    
    private func xAxisDates(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? store.scrollPosition.alignToDay()
        return (0..<pageDays).map { start.addDays($0).middleOfDay() }
    }
    
    private func xAxisBoundaries(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? store.scrollPosition.alignToDay()
        return (0...pageDays).map { start.addDays($0) }
    }
    
    private var axisChart: some View {
        let visible = store.pages[safe: visiblePageIndex]
        let start = store.scrollPosition.alignToDay()
        let endExclusive = start.addDays(pageDays)
        let fallbackXDomain = start...endExclusive
        
        // 축만 그리는 차트. `Chart {}` 는 EmptyView 를 ChartContent 로 쓰는데
        // 그 conformance 가 iOS 27+ 라 경고가 난다. 빈 컬렉션으로 마크 0개를 그린다.
        return Chart([Int](), id: \.self) { _ in
            RuleMark(y: .value("", 0))
        }
            .chartXScale(domain: visible?.xDomain ?? fallbackXDomain)
            .chartYScale(domain: store.yScale)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(CarveColor.divider)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))")
                                .font(CarveTypography.caption)
                                .foregroundStyle(CarveColor.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisBoundaries(for: visible)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.clear)
                    AxisValueLabel {
                        Text(" ")
                            .font(.caption2)
                            .foregroundStyle(.clear)
                    }
                }
            }
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
                            let positionX = min(max(xPosition, plotFrame.minX + 22), plotFrame.maxX - 22)
                            // ko 「9월 4일 금」 · en 「Fri Sep 4」 — 날짜와 요일의 순서를 카탈로그가 정한다.
                            Text(
                                "\(date.chartShortMonthDayText(locale: locale)) \(date.chartWeekdayText(locale: locale))",
                                bundle: .module,
                                comment: "차트 X축 날짜 라벨 — 월 · 일, 요일. 예: 9월 4일 금 · Fri Sep 4"
                            )
                            .font(CarveTypography.caption)
                            .monospacedDigit()
                            .foregroundStyle(CarveColor.secondary)
                            .position(x: positionX, y: plotFrame.maxY + 12)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
    }
    
    private var pager: some View {
        HStack(spacing: 0) {
            pageChart(store.pages[safe: 0], allowsSelection: false)
                .frame(width: store.pageWidth)
                .opacity(store.canMoveToPreviousWeek ? 1 : 0)
            
            pageChart(store.pages[safe: 1], allowsSelection: true)
                .frame(width: store.pageWidth)
            
            pageChart(store.pages[safe: 2], allowsSelection: false)
                .frame(width: store.pageWidth)
                .opacity(store.canMoveToNextWeek ? 1 : 0)
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
    
    private func pageChart(_ page: ChartPage?, allowsSelection: Bool) -> some View {
        let start = store.scrollPosition.alignToDay()
        let endExclusive = start.addDays(pageDays)
        let fallbackXDomain = start...endExclusive
        
        return Chart(page?.entries ?? []) { record in
            let isSelected = allowsSelection
                && store.selectedDate.map { Calendar.current.isDate(record.date, inSameDayAs: $0) } == true
            
            BarMark(
                x: .value(ChartCatalog.string("날짜", locale: locale), record.date.middleOfDay(), unit: .day),
                y: .value(ChartCatalog.string("필사량", locale: locale), record.count),
                width: .ratio(0.55)
            )
            .cornerRadius(6)
            .foregroundStyle(CarveColor.accent)
            .opacity(isSelected ? 1 : 0.88)
            .annotation(position: .top, alignment: .center) {
                if record.hasDrawing {
                    Text("\(record.count)")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.accent)
                        .padding(.vertical, CarveSpacing.xxSmall)
                        .padding(.horizontal, CarveSpacing.xSmall)
                        .background(CarveColor.selected)
                        .clipShape(Capsule())
                } else {
                    Text("\(record.count)")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.divider)
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
