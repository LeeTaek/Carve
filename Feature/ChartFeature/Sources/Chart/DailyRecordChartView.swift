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
//import ComposableArchitecture

/// 하루 단위 필사량을 주간 단위로 페이징하여 보여주는 차트.
/// 페이징 스크롤이 원하는대로 구현이 안되서 무한 스크롤 아이디어 차용,
/// 뒤에 축을 표시한 Chart위에 페이징용 스크롤 덮어서 구현
struct DailyRecordChartView: View {
    let records: [DailyRecord]
    @Binding var scrollPosition: Date
    @Binding var selectedDate: Date?
    let lowerBoundDate: Date
    
    private let lightBlue = Color(hex: 0x76DAF0)
    private let primaryBlue = Color(hex: 0x089CF5)
    
    // MARK: - Paging (MeasurementChartView 스타일: 이전/현재/다음 3페이지 + 항상 가운데로 복귀)
    
    private let visiblePageIndex = 1
    /// 한 페이지에 보여줄 일수(현재 7일)
    private let pageDays: Int = 7
    
    @State private var pageWidth: CGFloat = 0
    @State private var dragX: CGFloat = 0
    @State private var isScrolling: Bool = false
    
    /// 3페이지(이전/현재/다음)만 유지
    @State private var pages: [ChartPage] = []
    
    /// Y축 스케일(가운데 페이지 기준)
    @State private var yScale: ClosedRange<Double> = 0...1
    
    /// 페이징 애니메이션 이후, 데이터 윈도우를 갱신하고 가운데로 복귀시키기 위한 작업
    @State private var pagingTask: Task<Void, Never>?
    
    private var upperBoundDate: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    /// X축에 반드시 표시할 날짜 목록(현재 페이지 기준으로 pageDays개)
    private func xAxisDates(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? clampAnchorStart(scrollPosition)
        return (0..<pageDays).map { start.addDays($0).middleOfDay() }
    }
    
    /// X축 그리드/틱(세로 점선)은 날짜 경계(00:00)에 둔다. (pageDays+1개)
    private func xAxisBoundaries(for page: ChartPage?) -> [Date] {
        let start = page?.start ?? clampAnchorStart(scrollPosition)
        return (0...pageDays).map { start.addDays($0) }
    }
    
    var body: some View {
        if records.isEmpty {
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
                    pageWidth = geo.size.width
                    rebuildPagesIfNeeded()
                }
                .onChange(of: geo.size.width) { _, newValue in
                    pageWidth = newValue
                }
                .onChange(of: records) { _, _ in
                    rebuildPagesIfNeeded(force: true)
                }
                .onChange(of: scrollPosition) { _, _ in
                    // 부모가 scrollPosition을 바꿔도(예: 오늘 기준으로 초기화) 페이지를 재구성
                    rebuildPagesIfNeeded(force: true)
                }
            }
            .frame(height: UIScreen.main.bounds.height / 3)
        }
    }
    
    // MARK: - Subviews
    private var axisChart: some View {
        let visible = pages[safe: visiblePageIndex]
        
        return Chart {
            if let selectedDate {
                RuleMark(x: .value("날짜", selectedDate.middleOfDay(), unit: .day))
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .foregroundStyle(Color.secondary.opacity(0.3))
            }
        }
        .chartXScale(domain: visible?.xDomain ?? fallbackXDomain)
        .chartYScale(domain: yScale)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))")
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                        // X축 라벨 영역(플롯 하단 바로 아래)에 배치
                            .position(x: x, y: plotFrame.maxY + 12)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    private var pager: some View {
        HStack(spacing: 0) {
            // 이전/현재/다음 페이지 (가운데만 selection 허용)
            pageChart(pages[safe: 0], allowsSelection: false)
                .frame(width: pageWidth)
            
            pageChart(pages[safe: 1], allowsSelection: true)
                .frame(width: pageWidth)
            
            pageChart(pages[safe: 2], allowsSelection: false)
                .frame(width: pageWidth)
        }
        .offset(x: (-pageWidth * CGFloat(visiblePageIndex)) + dragX)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    isScrolling = true
                    // 드래그 중에는 선택 해제(MeasurementChartView와 동일한 UX)
                    if selectedDate != nil {
                        selectedDate = nil
                    }
                    dragX = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = max(60, pageWidth * 0.15)
                    let translation = value.translation.width
                    
                    // 이동 방향 결정
                    let move: PageMove
                    if translation > threshold {
                        move = canMove(.prev) ? .prev : .stay
                    } else if translation < -threshold {
                        move = canMove(.next) ? .next : .stay
                    } else {
                        move = .stay
                    }
                    
                    animateAndCommit(move)
                }
        )
        .clipped()
    }
    
    private func pageChart(_ page: ChartPage?, allowsSelection: Bool) -> some View {
        let page = page
        
        return Chart(page?.entries ?? []) { record in
            let isSelected = allowsSelection
            && selectedDate.map { Calendar.current.isDate(record.date, inSameDayAs: $0) } == true
            
            BarMark(
                x: .value("날짜", record.date.middleOfDay(), unit: .day),
                y: .value("필사량", record.count),
                width: .ratio(0.55)
            )
            .cornerRadius(6)
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [lightBlue, primaryBlue]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .opacity(isSelected ? 1.0 : 0.65)
            .annotation(position: .top, alignment: .center) {
                if isSelected {
                    Text("\(record.count)")
                        .font(.caption2)
                        .foregroundStyle(primaryBlue)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(.ultraThinMaterial)
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
        .chartYScale(domain: yScale)
        // 가운데 페이지에만 selection 허용
        .chartXSelection(value: allowsSelection ? $selectedDate : .constant(nil))
    }
    
    // MARK: - Paging Logic
    private func rebuildPagesIfNeeded(force: Bool = false) {
        let aligned = scrollPosition.alignToDay()
        
        if force || pages.isEmpty || pages[visiblePageIndex].start != aligned {
            pages = make3Pages(anchorStart: aligned)
            // 초기 구성은 즉시 반영(애니메이션 없이)
            yScale = targetYScale(for: pages) ?? yScale
        }
    }
    
    private func animateAndCommit(_ move: PageMove) {
        pagingTask?.cancel()
        
        let targetOffset: CGFloat
        switch move {
        case .prev: targetOffset = 0
        case .stay: targetOffset = -pageWidth * CGFloat(visiblePageIndex)
        case .next: targetOffset = -pageWidth * 2
        }
        
        withAnimation(.easeOut(duration: 0.22)) {
            dragX = targetOffset - (-pageWidth * CGFloat(visiblePageIndex))
        }
        
        pagingTask = Task { @MainActor in
            // 애니메이션 종료를 살짝 기다린 뒤 데이터 윈도우 교체 + 가운데로 복귀
            try? await Task.sleep(nanoseconds: 240_000_000)
            
            let newAnchor: Date
            switch move {
            case .prev:
                newAnchor = pages[visiblePageIndex].start.addDays(-pageDays)
            case .stay:
                newAnchor = pages[visiblePageIndex].start
            case .next:
                newAnchor = pages[visiblePageIndex].start.addDays(pageDays)
            }
            
            // scrollPosition을 부모와 동기화 ("현재 페이지" 기준 값)
            scrollPosition = clampAnchorStart(newAnchor)
            
            // 3페이지 재구성
            let newPages = make3Pages(anchorStart: scrollPosition)
            let newTarget = targetYScale(for: newPages)
            
            // 스케일 확장/축소에 따라 업데이트 순서를 달리해 '튀는' 느낌을 완화
            if let newTarget, newTarget.upperBound > yScale.upperBound {
                // 확장: 먼저 축을 늘리고 페이지를 교체
                animateYScale(to: newTarget)
                pages = newPages
            } else {
                // 축소(또는 유지): 먼저 페이지를 교체하고 축을 줄임
                pages = newPages
                animateYScale(to: newTarget)
            }
            
            // 항상 가운데로 복귀
            dragX = 0
            isScrolling = false
        }
    }
    
    private func canMove(_ move: PageMove) -> Bool {
        let start = pages[safe: visiblePageIndex]?.start ?? scrollPosition.alignToDay()
        let minStart = clampAnchorStart(lowerBoundDate)
        let maxStart = clampAnchorStart(upperBoundDate.addDays(-(pageDays - 1)))
        
        switch move {
        case .prev:
            return start.addDays(-pageDays) >= minStart
        case .next:
            return start.addDays(pageDays) <= maxStart
        case .stay:
            return true
        }
    }
    
    // MARK: - Page Construction
    
    private func make3Pages(anchorStart: Date) -> [ChartPage] {
        let anchor = clampAnchorStart(anchorStart.alignToDay())
        
        let prevStart = clampAnchorStart(anchor.addDays(-pageDays))
        let nextStart = clampAnchorStart(anchor.addDays(pageDays))
        
        return [
            makePage(start: prevStart),
            makePage(start: anchor),
            makePage(start: nextStart)
        ]
    }
    
    private func makePage(start: Date) -> ChartPage {
        let start = start.alignToDay()
        let end = start.addDays(pageDays - 1)
        let endExclusive = start.addDays(pageDays) // 다음날 00:00 (exclusive)
        
        let entries = records
            .filter {
                let day = $0.date.alignToDay() // 시간 제거
                return day >= start && day < endExclusive
            }
            .sorted { $0.date < $1.date }
        
        return ChartPage(
            start: start,
            end: end,
            entries: entries,
            xDomain: start...endExclusive
        )
    }
    
    /// 페이지의 데이터 분포에 맞춰 Y축 스케일을 계산합니다.
    /// - Returns: 페이지가 비어 있으면(nil) Y축을 유지(리사이즈 생략)하도록 nil을 반환합니다.
    private func targetYScale(for pages: [ChartPage]) -> ClosedRange<Double>? {
        let allCounts = pages.flatMap { $0.entries.map(\.count) }
        guard let maxInt = allCounts.max(), maxInt > 0 else { return nil }
        
        let top = max(1, Double(maxInt))
        let headroom = max(1, ceil(top * 0.4))   // 너가 쓰는 2/5(=0.4) 그대로
        return 0...(top + headroom)
    }
    
    private func targetYScale(for page: ChartPage?) -> ClosedRange<Double>? {
        guard let page else { return nil }
        return targetYScale(for: [page])
    }
    
    /// 현재 스케일과 목표 스케일 사이를 자연스럽게 전환합니다.
    /// - Note: 스케일이 커지는 경우(upperBound 증가)는 먼저 확장하고,
    ///         스케일이 줄어드는 경우는 먼저 페이지를 교체한 뒤 서서히 축소하여
    ///         BarMark가 '튀는' 느낌을 줄입니다.
    private func animateYScale(to target: ClosedRange<Double>?) {
        guard let target else { return }
        
        let currentUpper = yScale.upperBound
        let targetUpper = target.upperBound
        
        if targetUpper > currentUpper {
            let delta = max(0, targetUpper - currentUpper)
            let duration = min(0.38, max(0.20, 0.20 + (delta / max(1, currentUpper)) * 0.10))
            withAnimation(.easeInOut(duration: duration)) { yScale = target }
            
        } else if targetUpper < currentUpper {
            let hold = 0...max(currentUpper, targetUpper)
            yScale = hold
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 40_000_000)
                let delta = max(0, currentUpper - targetUpper)
                let duration = min(0.48, max(0.26, 0.26 + (delta / max(1, currentUpper)) * 0.18))
                withAnimation(.easeInOut(duration: duration)) { yScale = target }
            }
        }
    }
    
    // MARK: - Date Helpers
    /// anchorStart는 "7일 페이지"의 시작일이므로, lowerBound~today 범위에 맞춰 clamp
    private func clampAnchorStart(_ start: Date) -> Date {
        let cal = Calendar.current
        let minStart = cal.startOfDay(for: lowerBoundDate)
        let maxStart = cal.date(byAdding: .day, value: -(pageDays - 1), to: upperBoundDate) ?? upperBoundDate
        return min(max(start.alignToDay(), minStart), maxStart.alignToDay())
    }
    
    private var fallbackXDomain: ClosedRange<Date> {
        let start = clampAnchorStart(scrollPosition)
        let endExclusive = start.addDays(pageDays) // 다음날 00:00
        return start...endExclusive
    }
    
    // MARK: - Types
    
    private enum PageMove { case prev, stay, next }
    
    private struct ChartPage: Equatable {
        let start: Date
        let end: Date
        let entries: [DailyRecord]
        let xDomain: ClosedRange<Date>
    }
}


#Preview("Sample - 최근 20일") {
    DailyRecordChartPreview()
}

private struct DailyRecordChartPreview: View {
    @State private var scrollPosition: Date
    @State private var selectedDate: Date?
    
    private let records: [DailyRecord]
    private let lowerBoundDate: Date
    
    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        // 최근 20일 더미 데이터
        self.records = (0..<20).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyRecord(date: date, count: Int.random(in: 3...15))
        }
        .sorted { $0.date < $1.date }
        
        // 하한선: 오늘 - 30일
        self.lowerBoundDate = cal.date(byAdding: .day, value: -30, to: today) ?? today
        
        // 페이지 0 = [오늘-6 ... 오늘] 이 보이도록 초기 scrollPosition 설정
        _scrollPosition = State(initialValue: cal.date(byAdding: .day, value: -6, to: today) ?? today)
        _selectedDate = State(initialValue: today)
    }
    
    var body: some View {
        DailyRecordChartView(
            records: records,
            scrollPosition: $scrollPosition,
            selectedDate: $selectedDate,
            lowerBoundDate: lowerBoundDate
        )
        .padding()
    }
}
