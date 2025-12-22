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
        
        public init() {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let lower = cal.date(byAdding: .day, value: -30, to: today)!

            self.lowerBoundDate = lower
            self.earliestFetchedDate = today
            self.isAppendingPastData = false
            self.selectedRecord = nil

            self.dailyRecordChart = DailyRecordChartFeature.State(
                records: [],
                lowerBoundDate: lower,
                scrollPosition: today,
                selectedDate: nil
            )
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
            }
            
            return state
        }
    }
    
    @Dependency(\.drawingData) var drawingData
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        /// 비동기로 조회한 하루 단위 필사 기록을 상태에 반영.
        case setDailyRecords([DailyRecord])
        /// 과거 데이터 추가 로딩이 완료되었음을 알림.
        case endAppending
        case dailyRecordChart(DailyRecordChartFeature.Action)
        
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
        BindingReducer()
            .onChange(of: \.dailyRecordChart.selectedDate) { _, newValue in
                Reduce { state, _ in
                    handleSelectedDateChange(&state, newValue: newValue)
                }
            }
        
        Scope(state: \.dailyRecordChart, action: \.dailyRecordChart) {
            DailyRecordChartFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.fetchData):
                return handleFetchData()
                
            case .setDailyRecords(let dailyRecords):
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
                
            default: return .none
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
        let days = (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: -29 + offset, to: today)
        }
        
        let drawingData = self.drawingData
        
        return .run { send in
            var dailyRecords: [DailyRecord] = []
            for date in days {
                let count = try await drawingData.fetchDrawings(date: date)?.count ?? 0
                dailyRecords.append(.init(date: date, count: count))
            }
            await send(.setDailyRecords(dailyRecords))
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
    }
    
    /// 차트 위 심볼(데이터 포인트)을 탭했을 때 선택 상태를 갱신.
    private func handleTapSymbol(_ state: inout State, date: Date) {
        state.dailyRecordChart.selectedDate = date
        state.selectedRecord = state.dailyRecordChart.records.first(where: { $0.date == date })
    }
    
    /// 현재 스크롤 위치를 기준으로, 그 이전 주(과거 구간)의 데이터를 추가로 조회하는 Effect.
    private func handleLoadMoreBefore(_ state: inout State, referenceDate: Date) -> Effect<Action> {
        state.isAppendingPastData = true
        
        // 차트의 scrollPosition은 '보이는 X 도메인의 선두(leading) 값'으로 동작함.
        // prepend(과거 주 추가) 후에도 동일한 화면을 유지하려면
        // 선두 값을 '기존 선두 + 7일'로 보정해야 점프가 사라짐.
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
        
        return .run { send in
            var newRecords: [DailyRecord] = []
            for date in daysToAppend {
                let count = try await drawingData.fetchDrawings(date: date)?.count ?? 0
                newRecords.append(.init(date: date, count: count))
            }
            
            // 데이터 prepend
            await send(.setDailyRecords(newRecords + existingRecords))
            
            // 스크롤 선두 복원(점프 방지): 기존 선두 + 추가된 일 수
            let appendedDays = daysToAppend.count
            let compensated = cal.date(byAdding: .day, value: appendedDays, to: oldLeading) ?? oldLeading
            await send(.dailyRecordChart(.binding(.set(\.scrollPosition, compensated))))
            
            // 페이징 종료
            await send(.endAppending)
        }
    }
}
