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
public struct DrawingChartFeature {
    public init() { }
    
    @ObservableState
    public struct State {
        public static let initialState = Self()
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
        public var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
        
        public init() {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let lower = cal.date(byAdding: .day, value: -30, to: today)!
            
            self.lowerBoundDate = lower
            self.earliestFetchedDate = today
            self.isAppendingPastData = false
            self.selectedRecord = nil
            self.chapterCountsByDay = [:]
            self.dailyRecordChart = DailyRecordChartFeature.State(
                records: [],
                lowerBoundDate: lower,
                scrollPosition: today,
                selectedDate: nil
            )
            self.drawingWeeklySummary.scrollPosition = self.dailyRecordChart.scrollPosition
        }
    }
    
    @Dependency(\.drawingData) var drawingData
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        case setFetchedDailyData(dailyRecords: [DailyRecord], chapterCountsByDay: [Date: [BibleChapter: Int]])
        case setRecentItems(recentVerses: [RecentVerseItem], recentChapters: [BibleChapter])
        case endAppending
        case dailyRecordChart(DailyRecordChartFeature.Action)
        case drawingWeeklySummary(DrawingWeeklySummaryFeature.Action)
        
        public enum View {
            case fetchData
            case loadMoreBefore(Date)
            case tapSymbol(Date)
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
                case .view(.fetchData):
                    return handleFetchData()
                    
                case let .setFetchedDailyData(dailyRecords, chapterCountsByDay):
                    state.chapterCountsByDay = chapterCountsByDay
                    state.drawingWeeklySummary.chapterCountsByDay = chapterCountsByDay
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
    
    private func handleFetchData() -> Effect<Action> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let range = DateInterval(start: start, end: end)
        let days = (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
        let drawingData = self.drawingData
        
        return .run { send in
            let drawings = try await drawingData.fetchDrawings(in: range)
            let groupedByDay: [Date: [BibleDrawing]] = Dictionary(grouping: drawings) { drawing in
                calendar.startOfDay(for: drawing.updateDate ?? today)
            }
            let dailyRecords: [DailyRecord] = days
                .map { calendar.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }
            
            var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
            for day in days.map({ calendar.startOfDay(for: $0) }) {
                let dayDrawings = groupedByDay[day] ?? []
                var counts: [BibleChapter: Int] = [:]
                
                for drawing in dayDrawings {
                    guard let raw = drawing.titleName,
                          let title = BibleTitle(rawValue: raw),
                          let chapter = drawing.titleChapter
                    else { continue }
                    
                    let key = BibleChapter(title: title, chapter: chapter)
                    counts[key, default: 0] += 1
                }
                chapterCountsByDay[day] = counts
            }
            
            await send(.setFetchedDailyData(dailyRecords: dailyRecords, chapterCountsByDay: chapterCountsByDay))
            
            let recentDrawings = try await drawingData.fetchRecentDrawings(limit: 5)
            let sorted = recentDrawings.sorted { ($0.updateDate ?? .distantPast) > ($1.updateDate ?? .distantPast) }
            
            let recentVerses: [RecentVerseItem] = sorted.compactMap { drawing in
                RecentVerseItem(
                    verse: .init(
                        title: .init(
                            title: .init(rawValue: drawing.titleName ?? "") ?? .genesis,
                            chapter: drawing.titleChapter ?? 1
                        ),
                        verse: drawing.verse ?? 1,
                        sentence: ""
                    ),
                    updatedAt: drawing.updateDate ?? .distantFuture
                )
            }
            
            var seen = Set<BibleChapter>()
            let recentChapters: [BibleChapter] = sorted.compactMap { drawing in
                guard let titleRaw = drawing.titleName,
                      let title = BibleTitle(rawValue: titleRaw),
                      let chapter = drawing.titleChapter
                else { return nil }
                
                let key = BibleChapter(title: title, chapter: chapter)
                guard seen.insert(key).inserted else { return nil }
                return key
            }
            
            await send(.setRecentItems(recentVerses: recentVerses, recentChapters: recentChapters))
        }
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
        
        let drawingData = self.drawingData
        let existingRecords = state.dailyRecordChart.records
        let existingChapterCountsByDay = state.chapterCountsByDay
        
        return .run { send in
            let weekEnd = cal.date(byAdding: .day, value: 7, to: previousWeekStart)!
            let range = DateInterval(start: previousWeekStart, end: weekEnd)
            let drawings = try await drawingData.fetchDrawings(in: range)
            
            let groupedByDay: [Date: [BibleDrawing]] = Dictionary(grouping: drawings) { drawing in
                cal.startOfDay(for: drawing.updateDate ?? previousWeekStart)
            }
            
            let newRecords: [DailyRecord] = daysToAppend
                .map { cal.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }
            
            var newChapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
            for day in daysToAppend.map({ cal.startOfDay(for: $0) }) {
                let dayDrawings = groupedByDay[day] ?? []
                var counts: [BibleChapter: Int] = [:]
                
                for drawing in dayDrawings {
                    guard let titleRaw = drawing.titleName,
                          let title = BibleTitle(rawValue: titleRaw),
                          let titleChapter = drawing.titleChapter
                    else { continue }
                    let chapter = BibleChapter(title: title, chapter: titleChapter)
                    counts[chapter, default: 0] += 1
                }
                
                newChapterCountsByDay[day] = counts
            }
            
            var mergedChapterCounts = existingChapterCountsByDay
            for (day, counts) in newChapterCountsByDay {
                mergedChapterCounts[day] = counts
            }
            
            await send(
                .setFetchedDailyData(
                    dailyRecords: newRecords + existingRecords,
                    chapterCountsByDay: mergedChapterCounts
                )
            )
            
            let appendedDays = daysToAppend.count
            let compensated = cal.date(byAdding: .day, value: appendedDays, to: oldLeading) ?? oldLeading
            await send(.dailyRecordChart(.binding(.set(\.scrollPosition, compensated))))
            await send(.endAppending)
        }
    }
}
