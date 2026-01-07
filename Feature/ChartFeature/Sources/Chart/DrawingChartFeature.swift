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

        /// fetch한 데이터 중 가장 오래된 날짜
        /// 과거 구간을 추가 로딩할지 여부를 판단하는 기준.
        public var earliestFetchedDate: Date = Calendar.current.startOfDay(for: Date())
        /// 스크롤/로딩 가능한 날짜의 하한선 (오늘 기준 -30일)
        public var lowerBoundDate: Date = {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return cal.date(byAdding: .day, value: -30, to: today)!
        }()
        /// 과거 데이터를 추가로 불러오는 중인지 나타내는 플래그.(중복 로딩 방지용)
        public var isAppendingPastData: Bool = false
        /// 선택된 날짜에 해당하는 `DailyRecord` (차트 선택과 동기화)
        public var selectedRecord: DailyRecord?
        /// 날짜별(하루)로 장(Chapter) 단위 필사 절 수를 집계한 값.
        /// - Key: startOfDay(Date)
        /// - Value: [BibleChapter: verseCount]
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
        
        /// Xcode 프리뷰에서 사용할 더미.
        static var previewState: Self {
            var state = Self.initialState
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            state.dailyRecordChart.records = (0..<20).compactMap { day in
                let date = calendar.date(byAdding: .day, value: -day, to: today)!
                return DailyRecord(date: date, count: Int.random(in: 3...15))
            }
            state.dailyRecordChart.lowerBoundDate = state.lowerBoundDate
            
            // 가장 최근 날짜 기준으로 scrollPosition 맞추기
            if let latest = state.dailyRecordChart.records.map(\.date).max() {
                // 보이는 도메인(7일)의 leading 값이 되도록 -6일
                state.dailyRecordChart.scrollPosition = calendar.date(byAdding: .day, value: -6, to: latest) ?? latest
                state.dailyRecordChart.selectedDate = latest
                state.selectedRecord = state.dailyRecordChart.records.first { $0.date == latest }
                state.earliestFetchedDate = state.dailyRecordChart.records.map(\.date).min() ?? today
                state.drawingWeeklySummary.dailyRecords = state.dailyRecordChart.records
                state.drawingWeeklySummary.scrollPosition = state.dailyRecordChart.scrollPosition
                state.drawingWeeklySummary.chapterCountsByDay = state.chapterCountsByDay
            }
            
            return state
        }
    }
    
    @Dependency(\.drawingData) var drawingData
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        /// 비동기로 조회한 하루 단위 필사 기록 + 장(Chapter) 집계를 상태에 반영.
        case setFetchedDailyData(dailyRecords: [DailyRecord], chapterCountsByDay: [Date: [BibleChapter: Int]])
        /// 과거 데이터 추가 로딩이 완료되었음을 알림.
        case endAppending
        case dailyRecordChart(DailyRecordChartFeature.Action)
        case drawingWeeklySummary(DrawingWeeklySummaryFeature.Action)
        
        public enum View {
            /// 화면 진입 시(또는 새로고침 시) 차트 데이터를 조회.
            case fetchData
            /// 현재 스크롤 위치를 기준으로, 그 이전 주(과거 구간)의 데이터를 추가로 조회.
            case loadMoreBefore(Date)
            /// 차트 위 심볼(데이터 포인트)을 탭했을 때 해당 날짜를 선택.
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
                    
                case .view(.tapSymbol(let date)):
                    handleTapSymbol(&state, date: date)
                    return .none
                    
                case .view(.loadMoreBefore(let referenceDate)):
                    return handleLoadMoreBefore(&state, referenceDate: referenceDate)
                    
                case .endAppending:
                    state.isAppendingPastData = false
                    return .none
                    
                case .drawingWeeklySummary(.openVerse(let verse)):
                    return .none
                    
                case .drawingWeeklySummary(.openChapter(let chapter)):
                    return .none
                    
                default: return .none
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
    /// 선택된 날짜가 바뀌었을 때 선택된 레코드를 동기화.
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
    
    
    /// 화면 진입 시(또는 새로고침 시) 차트 데이터를 조회하는 비동기 Effect.
    private func handleFetchData() -> Effect<Action> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 최근 30일 (오늘 포함)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)! // 내일 0시 (exclusive)
        let range = DateInterval(start: start, end: end)
        
        // UI 도메인용 30일 날짜 목록 (0도 포함시키기 위함)
        let days = (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
        
        let drawingData = self.drawingData
        
        return .run { send in
            // 최근 30일치 drawing을 한 번에 가져오고, feature에서 날짜별로 집계.
            let drawings = try await drawingData.fetchDrawings(in: range)

            // 날짜별 그룹 (startOfDay 기준)
            let groupedByDay: [Date: [BibleDrawing]] = Dictionary(grouping: drawings) { drawing in
                calendar.startOfDay(for: drawing.updateDate!)
            }

            // UI 도메인 30일(빈 날 포함)을 DailyRecord로 변환
            let dailyRecords: [DailyRecord] = days
                .map { calendar.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }

            // 날짜별 장(Chapter) 단위 집계 (UI 도메인 30일 기준, 빈 날 포함)
            var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
            for day in days.map({ calendar.startOfDay(for: $0) }) {
                let dayDrawings = groupedByDay[day] ?? []
                var counts: [BibleChapter: Int] = [:]

                for drawing in dayDrawings {
                    guard let title = BibleTitle(rawValue: drawing.titleName!) else { continue }
                    let chapter = BibleChapter(title: title, chapter: drawing.titleChapter!)
                    counts[chapter, default: 0] += 1
                }

                chapterCountsByDay[day] = counts
            }

            await send(.setFetchedDailyData(dailyRecords: dailyRecords, chapterCountsByDay: chapterCountsByDay))
        }
    }
    
    /// 비동기로 조회한 하루 단위 필사 기록을 상태에 반영하고 초기 스크롤/선택 상태를 설정.
    private func handleSetDailyRecords(_ state: inout State, dailyRecords: [DailyRecord]) {
        state.dailyRecordChart.records = dailyRecords
        state.dailyRecordChart.lowerBoundDate = state.lowerBoundDate
        
        let calendar = Calendar.current
        
        // 가장 오래된 날짜(earliestFetchedDate) 설정
        if let earliest = dailyRecords.first?.date {
            state.earliestFetchedDate = calendar.startOfDay(for: earliest)
        }
        
        // 가장 최근 날짜(오늘 기준)를 중심으로 초기 스크롤 위치 설정
        if let latest = dailyRecords.last?.date {
            let latestDay = calendar.startOfDay(for: latest)
            // 한 페이지 길이가 7일이므로, 마지막 날짜를 포함하는 7일 구간의 선두값을 계산
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
    
    /// 차트 위 심볼(데이터 포인트)을 탭했을 때 선택 상태를 갱신.
    private func handleTapSymbol(_ state: inout State, date: Date) {
        state.dailyRecordChart.selectedDate = date
        state.selectedRecord = state.dailyRecordChart.records.first(where: { $0.date == date })
    }
    
    /// 현재 스크롤 위치를 기준으로, 그 이전 주(과거 구간)의 데이터를 추가로 조회하는 Effect.
    private func handleLoadMoreBefore(_ state: inout State, referenceDate: Date) -> Effect<Action> {
        state.isAppendingPastData = true
        let oldLeading = state.dailyRecordChart.scrollPosition
        let cal = Calendar.current
        
        // 우리가 가진 가장 과거의 주를 기준으로, 그 이전 주만 1회 확장
        guard let currentEarliestWeek = cal.dateInterval(of: .weekOfYear, for: state.earliestFetchedDate) else {
            return .send(.endAppending)
        }
        let startOfCurrentEarliestWeek = currentEarliestWeek.start
        
        // 이전 주의 시작
        guard let previousWeekStart = cal.date(byAdding: .day, value: -7, to: startOfCurrentEarliestWeek) else {
            return .send(.endAppending)
        }
        
        // 완전 범위 밖: 더 불러오지 않음
        if previousWeekStart < state.lowerBoundDate && state.earliestFetchedDate <= state.lowerBoundDate {
            return .send(.endAppending)
        }
        
        // 추가할 구간 계산 (하한선과 겹치는 부분만 잘라서 포함)
        let daysToAppend: [Date] = (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: previousWeekStart) else { return nil }
            return day >= state.lowerBoundDate ? cal.startOfDay(for: day) : nil
        }
        
        // 하한선 넘어 완전히 벗어나면 중단
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
                cal.startOfDay(for: drawing.updateDate!)
            }

            let newRecords: [DailyRecord] = daysToAppend
                .map { cal.startOfDay(for: $0) }
                .map { day in
                    let count = groupedByDay[day]?.count ?? 0
                    return DailyRecord(date: day, count: count)
                }

            // 날짜별 장(Chapter) 단위 집계 (prepend 구간)
            var newChapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
            for day in daysToAppend.map({ cal.startOfDay(for: $0) }) {
                let dayDrawings = groupedByDay[day] ?? []
                var counts: [BibleChapter: Int] = [:]

                for drawing in dayDrawings {
                    guard let title = BibleTitle(rawValue: drawing.titleName!) else { continue }
                    let chapter = BibleChapter(title: title, chapter: drawing.titleChapter!)
                    counts[chapter, default: 0] += 1
                }

                newChapterCountsByDay[day] = counts
            }

            // 기존 집계와 병합 (prepend 구간 날짜 키는 새로 추가되는 값)
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
            
            // 스크롤 선두 복원(점프 방지): 기존 선두 + 추가된 일 수
            let appendedDays = daysToAppend.count
            let compensated = cal.date(byAdding: .day, value: appendedDays, to: oldLeading) ?? oldLeading
            await send(.dailyRecordChart(.binding(.set(\.scrollPosition, compensated))))
            
            // 페이징 종료
            await send(.endAppending)
        }
    }
}
