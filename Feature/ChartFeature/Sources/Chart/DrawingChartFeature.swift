//
//  DrawingChartFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import Foundation
import CarveToolkit

import ComposableArchitecture

@Reducer
public struct DrawingChartFeature: Sendable {
    public init() { }
    
    @ObservableState
    public struct State {
        /// 처음 상태. 광고 자리(`SponsorAdSlotFeature.State` 의 `UIView`)를 담아 `Sendable` 이 아니므로 저장하지 않고 매번 만든다.
        public static var initialState: Self { Self() }
        var dailyRecordChart: DailyRecordChartFeature.State
        var drawingWeeklySummary: DrawingWeeklySummaryFeature.State = .init()
        public var earliestFetchedDate: Date = Calendar.current.startOfDay(for: Date())
        public var lowerBoundDate: Date = {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return cal.date(byAdding: .day, value: -30, to: today)!
        }()
        public var isAppendingPastData: Bool = false
        public var selectedRecord: DailyRecord?
        /// 날짜(자정)별 · 장(번역본 포함)별 필사 수 — 모든 필사책을 합산한다(2.2 결정 10). 과거 주를 더 불러오면 그 날들을 더한다.
        public var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
        /// 날짜(자정)별 · 장(번역본 포함)별로 그날 그 장을 마지막으로 쓴 필사책 — `chapterCountsByDay` 와 같은 행 · 같은 키로 만든다.
        public var chapterNotebooksByDay: [Date: [BibleChapter: NotebookID]] = [:]
        
        public init() {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let lower = cal.date(byAdding: .day, value: -30, to: today)!
            
            self.lowerBoundDate = lower
            self.earliestFetchedDate = today
            self.isAppendingPastData = false
            self.selectedRecord = nil
            self.chapterCountsByDay = [:]
            self.chapterNotebooksByDay = [:]
            self.dailyRecordChart = DailyRecordChartFeature.State(
                records: [],
                lowerBoundDate: lower,
                scrollPosition: today,
                selectedDate: nil
            )
            self.drawingWeeklySummary.scrollPosition = self.dailyRecordChart.scrollPosition
        }
    }
    
    /// 기간별 · 최근 필사 활동을 읽는다.
    @Dependency(\.drawingActivityRepository) var drawingActivityRepository
    /// 조회 범위의 기준이 되는 오늘을 읽는다.
    @Dependency(\.date) var date
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        /// 첫 조회 · 과거 주 추가 조회가 날짜별 수와 장별 수 · 장별 마지막 필사책을 모았을 때 발생한다.
        case setFetchedDailyData(
            dailyRecords: [DailyRecord],
            chapterCountsByDay: [Date: [BibleChapter: Int]],
            chapterNotebooksByDay: [Date: [BibleChapter: NotebookID]]
        )
        /// 첫 조회가 최근 절 · 장(그 행의 필사책 · 번역본 장)을 모았을 때 발생한다.
        case setRecentItems(recentVerses: [RecentVerseItem], recentChapters: [NotebookChapter])
        case endAppending
        case dailyRecordChart(DailyRecordChartFeature.Action)
        case drawingWeeklySummary(DrawingWeeklySummaryFeature.Action)
        case delegate(Delegate)
        
        public enum View {
            /// 빈 상태에서 필사 화면으로 돌아가려 할 때 발생한다.
            case backToWriting
            /// 차트 진입 시 데이터를 불러오기 위해 발생한다.
            case fetchData
            /// 과거 데이터가 더 필요할 때 발생한다.
            case loadMoreBefore(Date)
            /// 차트의 날짜 막대를 선택했을 때 발생한다.
            case tapSymbol(Date)
        }

        public enum Delegate {
            /// 차트를 닫고 필사 화면으로 돌아가도록 부모에 알린다.
            case backToWriting
        }
    }
    
    public var body: some Reducer<State, Action> {
        CombineReducers {
            BindingReducer()
            
            Scope(state: \.dailyRecordChart, action: \.dailyRecordChart) {
                DailyRecordChartFeature()
            }
            
            Scope(state: \.drawingWeeklySummary, action: \.drawingWeeklySummary) {
                DrawingWeeklySummaryFeature()
            }
            
            Reduce { state, action in
                switch action {
                case .view(.backToWriting):
                    return .send(.delegate(.backToWriting))

                case .view(.fetchData):
                    return handleFetchData()
                    
                case let .setFetchedDailyData(dailyRecords, chapterCountsByDay, chapterNotebooksByDay):
                    state.chapterCountsByDay = chapterCountsByDay
                    state.chapterNotebooksByDay = chapterNotebooksByDay
                    state.drawingWeeklySummary.chapterCountsByDay = chapterCountsByDay
                    state.drawingWeeklySummary.chapterNotebooksByDay = chapterNotebooksByDay
                    handleSetDailyRecords(&state, dailyRecords: dailyRecords)
                    return .none
                    
                case let .setRecentItems(recentVerses, recentChapters):
                    state.drawingWeeklySummary.recentVerses = recentVerses
                    state.drawingWeeklySummary.recentChapters = recentChapters
                    return .none
                    
                case .view(.tapSymbol(let date)):
                    handleTapSymbol(&state, date: date)
                    return .none
                    
                case .view(.loadMoreBefore(let referenceDate)):
                    return handleLoadMoreBefore(&state, referenceDate: referenceDate)
                    
                case .endAppending:
                    state.isAppendingPastData = false
                    return .none
                    
                default:
                    return .none
                }
            }
        }
        .onChange(of: \.dailyRecordChart.selectedDate) { _, newValue in
            Reduce { state, _ in
                handleSelectedDateChange(&state, newValue: newValue)
            }
        }
        .onChange(of: \.dailyRecordChart.scrollPosition) { _, newValue in
            Reduce { state, _ in
                state.drawingWeeklySummary.scrollPosition = newValue
                return .none
            }
        }
    }
}

extension DrawingChartFeature {
    private func handleSelectedDateChange(
        _ state: inout State,
        newValue: Date?
    ) -> Effect<Action> {
        if let newValue {
            state.selectedRecord = state.dailyRecordChart.records.first(
                where: { $0.date == newValue }
            )
        } else {
            state.selectedRecord = nil
        }
        return .none
    }
    
    /// 오늘(`date.now`)부터 30일치 기록과 최근 필사 항목을 불러온다 — 모든 필사책의 행을 합산한다(2.2 결정 10).
    private func handleFetchData() -> Effect<Action> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date.now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let range = DateInterval(start: start, end: end)
        let days = (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
        let drawingActivityRepository = self.drawingActivityRepository
        
        return .run { send in
            let drawings = try await drawingActivityRepository.activities(in: range)
            // 날짜별 수는 모든 필사책 · 번역본의 행 수다 — 필사책 · 권을 풀지 못하는 행도 센다.
            let groupedByDay: [Date: [DrawingActivity]] = Dictionary(grouping: drawings) { drawing in
                calendar.startOfDay(for: drawing.updateDate ?? today)
            }
            let dailyRecords: [DailyRecord] = days
                .map { calendar.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }
            
            var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
            var chapterNotebooksByDay: [Date: [BibleChapter: NotebookID]] = [:]
            for day in days.map({ calendar.startOfDay(for: $0) }) {
                let tally = Self.chapterTally(of: groupedByDay[day] ?? [])
                chapterCountsByDay[day] = tally.counts
                chapterNotebooksByDay[day] = tally.notebooks
            }
            
            await send(
                .setFetchedDailyData(
                    dailyRecords: dailyRecords,
                    chapterCountsByDay: chapterCountsByDay,
                    chapterNotebooksByDay: chapterNotebooksByDay
                )
            )
            
            let recentDrawings = try await drawingActivityRepository.recentActivities(limit: 5)
            let sorted = recentDrawings.sorted { ($0.updateDate ?? .distantPast) > ($1.updateDate ?? .distantPast) }
            
            // 최근 절은 그 행의 필사책 · 번역본 장(`DrawingActivity.page`)으로 담아 누르면 그 필사책 · 번역본 절로 연다(2.2 결정 10).
            // 필사책 · 권 · 번역본을 모르거나 장이 없는 행은 건너뛴다 — 창세기나 기본 필사책 등 다른 자리로 바꿔 보이지 않는다.
            let recentVerses: [RecentVerseItem] = sorted.compactMap { drawing in
                guard let page = drawing.page else { return nil }
                return RecentVerseItem(
                    verse: BibleVerse(title: page.chapter, verse: drawing.verse ?? 1, sentence: ""),
                    updatedAt: drawing.updateDate ?? .distantFuture,
                    notebook: page.notebook
                )
            }
            
            // 장은 필사책을 합산해 겹치지 않게 — 같은 장을 여러 필사책에서 썼으면 한 줄이고, 가장 최근 행의 필사책으로 연다.
            // 같은 권 · 장이라도 번역본이 다르면 다른 장이다.
            var seen = Set<BibleChapter>()
            let recentChapters: [NotebookChapter] = sorted.compactMap { drawing in
                guard let page = drawing.page, seen.insert(page.chapter).inserted else { return nil }
                return page
            }
            
            await send(.setRecentItems(recentVerses: recentVerses, recentChapters: recentChapters))
        }
    }
    
    /// 역할: 하루치 활동을 장(번역본 포함)별로 센다 — 모든 필사책을 합산하고(2.2 결정 10), 그날 그 장을 마지막으로 쓴 필사책을 함께 적는다.
    /// 입력 · 출력: 하루치 활동 → 장별 수 · 장별 마지막 필사책(같은 키). 같은 권 · 장도 번역본이 다르면 따로 센다.
    ///   필사책 · 권 · 번역본을 풀지 못하거나(`DrawingActivity.page` 가 nil — 모르는 권 · 깨진 필사책 접두) 장이 없는 행은
    ///   날짜별 수에만 들고 여기서는 건너뛴다. 고친 시각이 같으면 먼저 온 행의 필사책을 둔다.
    /// 부작용: 없음.
    private static func chapterTally(
        of drawings: [DrawingActivity]
    ) -> (counts: [BibleChapter: Int], notebooks: [BibleChapter: NotebookID]) {
        var counts: [BibleChapter: Int] = [:]
        var latest: [BibleChapter: (notebook: NotebookID, updateDate: Date)] = [:]
        for drawing in drawings {
            guard let page = drawing.page else { continue }
            counts[page.chapter, default: 0] += 1
            let updateDate = drawing.updateDate ?? .distantPast
            if let current = latest[page.chapter], current.updateDate >= updateDate { continue }
            latest[page.chapter] = (page.notebook, updateDate)
        }
        return (counts, latest.mapValues { $0.notebook })
    }
    
    private func handleSetDailyRecords(_ state: inout State, dailyRecords: [DailyRecord]) {
        state.dailyRecordChart.records = dailyRecords
        state.dailyRecordChart.lowerBoundDate = state.lowerBoundDate
        
        let calendar = Calendar.current
        if let earliest = dailyRecords.first?.date {
            state.earliestFetchedDate = calendar.startOfDay(for: earliest)
        }
        
        if let latest = dailyRecords.last?.date {
            let latestDay = calendar.startOfDay(for: latest)
            let leading = calendar.date(byAdding: .day, value: -6, to: latestDay) ?? latestDay
            state.dailyRecordChart.scrollPosition = leading
            state.dailyRecordChart.selectedDate = latestDay
            state.selectedRecord = dailyRecords.last
        } else {
            state.dailyRecordChart.selectedDate = nil
            state.selectedRecord = nil
        }
        state.drawingWeeklySummary.dailyRecords = state.dailyRecordChart.records
        state.drawingWeeklySummary.scrollPosition = state.dailyRecordChart.scrollPosition
        state.drawingWeeklySummary.chapterCountsByDay = state.chapterCountsByDay
        state.drawingWeeklySummary.chapterNotebooksByDay = state.chapterNotebooksByDay
    }
    
    private func handleTapSymbol(_ state: inout State, date: Date) {
        state.dailyRecordChart.selectedDate = date
        state.selectedRecord = state.dailyRecordChart.records.first(where: { $0.date == date })
    }
    
    private func handleLoadMoreBefore(_ state: inout State, referenceDate: Date) -> Effect<Action> {
        _ = referenceDate
        state.isAppendingPastData = true
        let oldLeading = state.dailyRecordChart.scrollPosition
        let cal = Calendar.current
        
        guard let currentEarliestWeek = cal.dateInterval(of: .weekOfYear, for: state.earliestFetchedDate) else {
            return .send(.endAppending)
        }
        let startOfCurrentEarliestWeek = currentEarliestWeek.start
        
        guard let previousWeekStart = cal.date(byAdding: .day, value: -7, to: startOfCurrentEarliestWeek) else {
            return .send(.endAppending)
        }
        
        if previousWeekStart < state.lowerBoundDate && state.earliestFetchedDate <= state.lowerBoundDate {
            return .send(.endAppending)
        }
        
        let daysToAppend: [Date] = (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: previousWeekStart) else { return nil }
            return day >= state.lowerBoundDate ? cal.startOfDay(for: day) : nil
        }
        
        guard !daysToAppend.isEmpty else {
            return .send(.endAppending)
        }
        
        let drawingActivityRepository = self.drawingActivityRepository
        let existingRecords = state.dailyRecordChart.records
        let existingChapterCountsByDay = state.chapterCountsByDay
        let existingChapterNotebooksByDay = state.chapterNotebooksByDay
        
        return .run { send in
            let weekEnd = cal.date(byAdding: .day, value: 7, to: previousWeekStart)!
            let range = DateInterval(start: previousWeekStart, end: weekEnd)
            let drawings = try await drawingActivityRepository.activities(in: range)
            
            let groupedByDay: [Date: [DrawingActivity]] = Dictionary(grouping: drawings) { drawing in
                cal.startOfDay(for: drawing.updateDate ?? previousWeekStart)
            }
            
            let newRecords: [DailyRecord] = daysToAppend
                .map { cal.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }
            
            // 첫 조회와 같은 규칙 — 필사책을 합산한 장(번역본 포함)으로 센다. 기존 날짜 값은 그대로 두고 붙인 날짜 값을 더한다.
            var mergedChapterCounts = existingChapterCountsByDay
            var mergedChapterNotebooks = existingChapterNotebooksByDay
            for day in daysToAppend.map({ cal.startOfDay(for: $0) }) {
                let tally = Self.chapterTally(of: groupedByDay[day] ?? [])
                mergedChapterCounts[day] = tally.counts
                mergedChapterNotebooks[day] = tally.notebooks
            }
            
            await send(
                .setFetchedDailyData(
                    dailyRecords: newRecords + existingRecords,
                    chapterCountsByDay: mergedChapterCounts,
                    chapterNotebooksByDay: mergedChapterNotebooks
                )
            )
            
            let appendedDays = daysToAppend.count
            let compensated = cal.date(byAdding: .day, value: appendedDays, to: oldLeading) ?? oldLeading
            await send(.dailyRecordChart(.binding(.set(\.scrollPosition, compensated))))
            await send(.endAppending)
        }
    }
}
