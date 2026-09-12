//
//  DailyRecordChartFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 12/19/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit

import ComposableArchitecture

struct ChartPage: Equatable {
    let start: Date
    let end: Date
    let entries: [DailyRecord]
    let xDomain: ClosedRange<Date>
}

@Reducer
public struct DailyRecordChartFeature {
    static let pageDays: Int = 7
    private let visiblePageIndex = 1
    
    public enum PageMove: Equatable { case prev, stay, next }
    private enum CancelID { case paging, yScale }
    
    @ObservableState
    public struct State: Equatable {
        static let initialState = Self()
        var records: [DailyRecord] = []
        var lowerBoundDate: Date = .distantPast
        var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        var selectedDate: Date?
        var pageWidth: CGFloat = 0
        var dragX: CGFloat = 0
        var isScrolling: Bool = false
        /// 페이지 전환 애니메이션 중 중복 드래그와 이동을 막는다.
        var isPaging: Bool = false
        var pages: [ChartPage] = []
        var yScale: ClosedRange<Double> = 0...1

        /// 현재 조회 범위에 실제 필사 기록이 하나라도 있는지 나타낸다.
        var hasWrittenRecord: Bool {
            records.contains(where: \.hasDrawing)
        }

        /// 현재 화면에 표시하는 7일 범위의 시작일이다.
        var visibleStartDate: Date {
            pages[safe: 1]?.start ?? scrollPosition.alignToDay()
        }

        /// 현재 화면에 표시하는 7일 범위의 마지막 날이다.
        var visibleEndDate: Date {
            pages[safe: 1]?.end ?? visibleStartDate.addDays(DailyRecordChartFeature.pageDays - 1)
        }

        /// 과거 7일로 이동할 수 있는지 나타낸다.
        var canMoveToPreviousWeek: Bool {
            visibleStartDate.addDays(-DailyRecordChartFeature.pageDays) >= lowerBoundDate.alignToDay()
        }

        /// 오늘을 포함하는 최신 7일 범위보다 앞으로 이동하지 않도록 제한한다.
        var canMoveToNextWeek: Bool {
            let today = Calendar.current.startOfDay(for: Date())
            return visibleStartDate.addDays(DailyRecordChartFeature.pageDays)
                <= today.addDays(-(DailyRecordChartFeature.pageDays - 1))
        }

        /// VoiceOver가 막대를 하나씩 탐색하지 않아도 주간 흐름을 알 수 있는 요약이다.
        var accessibilitySummary: String {
            let calendar = Calendar.current
            let start = visibleStartDate
            let end = visibleEndDate
            let entries = records.filter { record in
                let day = calendar.startOfDay(for: record.date)
                return start <= day && day <= end
            }
            let total = entries.reduce(0) { $0 + $1.count }
            let average = Double(total) / Double(DailyRecordChartFeature.pageDays)
            let maximum = entries.map(\.count).max() ?? 0
            let zeroDayCount = DailyRecordChartFeature.pageDays - entries.filter(\.hasDrawing).count
            let maximumDate = entries
                .filter { $0.count == maximum && maximum > 0 }
                .map(\.date)
                .min()

            let range = "\(start.chartMonthDayText)부터 \(end.chartMonthDayText)까지"
            let maximumText = maximumDate.map { "가장 많은 날은 \($0.chartMonthDayText) \(maximum)절" }
                ?? "가장 많은 날은 없어요"
            let zeroDayText: String
            switch zeroDayCount {
            case 0: zeroDayText = "기록 없는 날은 없어요"
            case 1: zeroDayText = "없는 날은 하루"
            case 2: zeroDayText = "없는 날은 이틀"
            default: zeroDayText = "없는 날은 \(zeroDayCount)일"
            }

            return "차트. \(range). 하루에 필사한 절 수. 모두 \(total)절, 하루 평균 \(average.formatted(.number.precision(.fractionLength(1))))절. \(maximumText), \(zeroDayText)."
        }
        
        init(
            records: [DailyRecord] = [],
            lowerBoundDate: Date = .distantPast,
            scrollPosition: Date = Calendar.current.startOfDay(for: Date()),
            selectedDate: Date? = nil
        ) {
            self.records = records
            self.lowerBoundDate = lowerBoundDate
            self.scrollPosition = scrollPosition
            self.selectedDate = selectedDate
        }
    }
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        case rebuild(force: Bool)
        case commitMove(PageMove)
        case finishMove(PageMove)
        case applyYScale(ClosedRange<Double>)
        
        public enum View {
            /// 이전 7일 버튼을 눌렀을 때 발생한다.
            case previousWeekTapped
            /// 다음 7일 버튼을 눌렀을 때 발생한다.
            case nextWeekTapped
            /// 차트 폭을 처음 측정했을 때 발생한다.
            case onAppear(width: CGFloat)
            /// 회전 등으로 차트 폭이 바뀌었을 때 발생한다.
            case widthChanged(CGFloat)
            /// 주간 차트를 드래그하는 동안 발생한다.
            case dragChanged(translationX: CGFloat)
            /// 주간 차트 드래그가 끝났을 때 발생한다.
            case dragEnded(translationX: CGFloat)
        }
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.scrollPosition) { _, _ in
                Reduce { state, _ in
                    rebuildPagesIfNeeded(&state)
                    return .none
                }
            }
            .onChange(of: \.records) { _, _ in
                Reduce { state, _ in
                    rebuildPagesIfNeeded(&state, force: true)
                    return .none
                }
            }
        
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
                
            case .rebuild(let force):
                rebuildPagesIfNeeded(&state, force: force)
                return .none
                
            case .commitMove(let move):
                return handleCommitMove(&state, move: move)
                
            case .finishMove(let move):
                return handleFinishMove(&state, move: move)
                
            case .applyYScale(let range):
                withAnimation(.easeInOut(duration: 0.34)) {
                    state.yScale = range
                }
                return .none

            case .view(.previousWeekTapped):
                guard state.canMoveToPreviousWeek else { return .none }
                return .send(.commitMove(.prev))

            case .view(.nextWeekTapped):
                guard state.canMoveToNextWeek else { return .none }
                return .send(.commitMove(.next))
                
            case .view(.onAppear(let width)):
                state.pageWidth = width
                return .send(.rebuild(force: true))
                
            case .view(.widthChanged(let width)):
                state.pageWidth = width
                return .none
                
            case .view(.dragChanged(let translationX)):
                guard !state.isPaging else { return .none }
                state.isScrolling = true
                state.selectedDate = nil

                let upperBoundDate = Calendar.current.startOfDay(for: Date())
                let maxOverscroll = min(32, state.pageWidth * 0.08)

                if translationX > 0, !canMove(.prev, state: state, upperBoundDate: upperBoundDate) {
                    state.dragX = rubberBand(translationX, maxOverscroll: maxOverscroll)
                } else if translationX < 0, !canMove(.next, state: state, upperBoundDate: upperBoundDate) {
                    state.dragX = rubberBand(translationX, maxOverscroll: maxOverscroll)
                } else {
                    let limit = state.pageWidth
                    let maxExtra = state.pageWidth * 0.15
                    let absT = abs(translationX)
                    if absT <= limit {
                        state.dragX = translationX
                    } else {
                        let extra = absT - limit
                        let dampedExtra = maxExtra * (extra / (extra + maxExtra))
                        let signed = (translationX >= 0 ? 1.0 : -1.0)
                        state.dragX = CGFloat(signed) * (limit + dampedExtra)
                    }
                }

                return .none
                
            case .view(.dragEnded(let translationX)):
                guard !state.isPaging else { return .none }
                let threshold: CGFloat = max(60, state.pageWidth * 0.15)
                let upperBoundDate = Calendar.current.startOfDay(for: Date())
                
                let move: PageMove = {
                    if translationX > threshold {
                        return canMove(.prev, state: state, upperBoundDate: upperBoundDate) ? .prev : .stay
                    } else if translationX < -threshold {
                        return canMove(.next, state: state, upperBoundDate: upperBoundDate) ? .next : .stay
                    } else {
                        return .stay
                    }
                }()
                
                return .send(.commitMove(move))
            }
        }
    }
}

extension DailyRecordChartFeature {
    private func rebuildPagesIfNeeded(_ state: inout State, force: Bool = false) {
        let aligned = state.scrollPosition.alignToDay()
        
        if force || state.pages.isEmpty || state.pages[safe: visiblePageIndex]?.start != aligned {
            let upperBoundDate = Calendar.current.startOfDay(for: Date())
            state.pages = make3Pages(
                anchorStart: aligned,
                records: state.records,
                lowerBoundDate: state.lowerBoundDate,
                upperBoundDate: upperBoundDate
            )
            
            if let scale = targetYScale(for: state.pages) {
                state.yScale = scale
            }
        }
    }
    
    private func canMove(_ move: PageMove, state: State, upperBoundDate: Date) -> Bool {
        let start = state.pages[safe: visiblePageIndex]?.start ?? state.scrollPosition.alignToDay()
        let minStart = clampAnchorStart(
            state.lowerBoundDate,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let maxStart = clampAnchorStart(
            upperBoundDate.addDays(-(Self.pageDays - 1)),
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        switch move {
        case .prev: return start.addDays(-Self.pageDays) >= minStart
        case .stay: return true
        case .next: return start.addDays(Self.pageDays) <= maxStart
        }
    }
    
    private func make3Pages(
        anchorStart: Date,
        records: [DailyRecord],
        lowerBoundDate: Date,
        upperBoundDate: Date
    ) -> [ChartPage] {
        let anchor = clampAnchorStart(
            anchorStart.alignToDay(),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let prevStart = clampAnchorStart(
            anchor.addDays(-Self.pageDays),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let nextStart = clampAnchorStart(
            anchor.addDays(Self.pageDays),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        return [
            makePage(start: prevStart, records: records),
            makePage(start: anchor, records: records),
            makePage(start: nextStart, records: records)
        ]
    }
    
    private func makePage(start: Date, records: [DailyRecord]) -> ChartPage {
        let start = start.alignToDay()
        let end = start.addDays(Self.pageDays - 1)
        let endExclusive = start.addDays(Self.pageDays)
        
        let entries = records
            .filter {
                let day = $0.date.alignToDay()
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
    
    func targetYScale(for pages: [ChartPage]) -> ClosedRange<Double>? {
        let allCounts = pages.flatMap { $0.entries.map(\.count) }
        guard let maxInt = allCounts.max(), maxInt > 0 else { return nil }
        
        let top = max(1, Double(maxInt))
        let headroom = max(1, ceil(top * 0.4))
        return 0...(top + headroom)
    }
    
    private func clampAnchorStart(
        _ start: Date,
        lowerBoundDate: Date,
        upperBoundDate: Date
    ) -> Date {
        let cal = Calendar.current
        let minStart = cal.startOfDay(for: lowerBoundDate)
        let maxStart = cal.date(byAdding: .day, value: -(Self.pageDays - 1), to: upperBoundDate) ?? upperBoundDate
        return min(max(start.alignToDay(), minStart), maxStart.alignToDay())
    }
    
    private func rubberBand(_ translationX: CGFloat, maxOverscroll: CGFloat) -> CGFloat {
        guard maxOverscroll > 0 else { return 0 }
        let trans = abs(translationX)
        let damped = maxOverscroll * (trans / (trans + maxOverscroll))
        return translationX >= 0 ? damped : -damped
    }
    
    private func handleCommitMove(_ state: inout State, move: PageMove) -> Effect<Action> {
        guard !state.isPaging else { return .none }
        let move = canMove(move, state: state, upperBoundDate: Calendar.current.startOfDay(for: Date())) ? move : .stay
        guard move != .stay else {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                state.dragX = 0
            }
            state.isScrolling = false
            return .none
        }

        state.isPaging = true
        let targetDelta: CGFloat = {
            switch move {
            case .prev: return state.pageWidth
            case .stay: return 0
            case .next: return -state.pageWidth
            }
        }()

        withAnimation(.easeOut(duration: 0.22)) {
            state.dragX = targetDelta
        }

        return .run { send in
            try? await Task.sleep(nanoseconds: 240_000_000)
            await send(.finishMove(move))
        }
        .cancellable(id: CancelID.paging, cancelInFlight: true)
    }

    private func handleFinishMove(_ state: inout State, move: PageMove) -> Effect<Action> {
        state.isPaging = false
        let upperBoundDate = Calendar.current.startOfDay(for: Date())
        
        let currentStart = state.pages[safe: visiblePageIndex]?.start ?? state.scrollPosition.alignToDay()
        let newAnchor: Date = {
            switch move {
            case .prev: return currentStart.addDays(-Self.pageDays)
            case .stay: return currentStart
            case .next: return currentStart.addDays(Self.pageDays)
            }
        }()
        
        state.scrollPosition = clampAnchorStart(
            newAnchor,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        let newPages = make3Pages(
            anchorStart: state.scrollPosition,
            records: state.records,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        let target = targetYScale(for: newPages)
        
        if let target {
            let currentUpper = state.yScale.upperBound
            let targetUpper = target.upperBound
            
            if targetUpper > currentUpper {
                withAnimation(.easeInOut(duration: 0.3)) { state.yScale = target }
                state.pages = newPages
            } else if targetUpper < currentUpper {
                state.pages = newPages
                state.yScale = 0...max(currentUpper, targetUpper)
                state.dragX = 0
                state.isScrolling = false
                
                return .run { send in
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    await send(.applyYScale(target))
                }
                .cancellable(id: CancelID.yScale, cancelInFlight: true)
            } else {
                state.pages = newPages
                state.yScale = target
            }
        } else {
            state.pages = newPages
        }
        
        state.dragX = 0
        state.isScrolling = false
        return .none
    }
}
