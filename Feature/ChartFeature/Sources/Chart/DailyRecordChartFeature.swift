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
    public struct State {
        static let initialState = Self()
        var records: [DailyRecord] = []
        var lowerBoundDate: Date = .distantPast
        var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        var selectedDate: Date?
        var pageWidth: CGFloat = 0
        var dragX: CGFloat = 0
        var isScrolling: Bool = false
        var pages: [ChartPage] = []
        var yScale: ClosedRange<Double> = 0...1
        
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
            case onAppear(width: CGFloat)
            case widthChanged(CGFloat)
            case dragChanged(translationX: CGFloat)
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
                
            case .view(.onAppear(let width)):
                state.pageWidth = width
                return .send(.rebuild(force: true))
                
            case .view(.widthChanged(let width)):
                state.pageWidth = width
                return .none
                
            case .view(.dragChanged(let translationX)):
                state.isScrolling = true
                state.selectedDate = nil

                let upperBoundDate = Calendar.current.startOfDay(for: Date())
                let maxOverscroll = min(120, state.pageWidth * 0.22)

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
        guard move != .stay else {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                state.dragX = 0
            }
            state.isScrolling = false
            return .none
        }

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
