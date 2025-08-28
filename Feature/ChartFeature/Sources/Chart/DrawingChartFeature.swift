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

public struct DailyRecord: Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var count: Int
}

@Reducer
public struct DrawingChartFeature {
    public init() { }
    @ObservableState
    public struct State {
        public static let initialState = Self()
        public var dailyRecords: [DailyRecord] = []
        public var scrollPosition: Date = .now
        /// fetch한 가장 오래된 날짜
        public var earliestFetchedDate: Date = Calendar.current.startOfDay(for: Date())
        
        /// 최대 하한선 (오늘 기준 -30일)
        public var lowerBoundDate: Date = {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return cal.date(byAdding: .day, value: -30, to: today)!
        }()
        /// 페이징 애니메이션
        public var isAppendingPastData: Bool = false
        
        public var selectedDate: Date?
        public var selectedRecord: DailyRecord?
    }
    
    @Dependency(\.drawingData) var drawingData
    
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        case setDailyRecords([DailyRecord])
        case endAppending
        
        public enum View {
            case fetchData
            case loadMoreBefore(Date)
            case tapSymbol(Date)
        }
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.scrollPosition) { old, new in
                Reduce { state, _ in
                    let calendar = Calendar.current
                    let oldDay = calendar.startOfDay(for: old)
                    let newDay = calendar.startOfDay(for: new)
                   
                    // 스크롤 방향이 오른쪽(미래) 또는 하루 변화 없음 → 무시
                    guard newDay < oldDay else { return .none }

                    // 초기 로딩 중이거나, 이미 페이징 중이면 무시
                    guard !state.dailyRecords.isEmpty, !state.isAppendingPastData else { return .none }

                    let prefetchDistanceDays = 1
                    let prefetchThreshold = calendar.date(byAdding: .day,
                                                          value: prefetchDistanceDays,
                                                          to: state.earliestFetchedDate)!

                    guard state.earliestFetchedDate > state.lowerBoundDate else { return .none }

                    if newDay <= prefetchThreshold {
                      return .send(.view(.loadMoreBefore(newDay)))
                    }
                    return .none
                }
            }
            .onChange(of: \.selectedDate) { _, newValue in
                Reduce { state, _ in
                    if let newValue {
                        state.selectedRecord = state.dailyRecords.first(where: { $0.date == newValue })
                    }
                    return .none
                }
            }
        
        Reduce { state, action in
            switch action {
            case .view(.fetchData):
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let week = (0..<7).map { offset in
                    calendar.date(byAdding: .day, value: -6 + offset, to: today)!
                }
            
                return .run { send in
                    var dailyRecords: [DailyRecord] = []
                    for date in week {
                        let count = try await drawingData.fetchDrawings(date: date)?.count ?? 0
                        dailyRecords.append(.init(date: date, count: count))
                    }
                    await send(.setDailyRecords(dailyRecords))
                }
            case .setDailyRecords(let dailyRecords):
                state.dailyRecords = dailyRecords
                if let firstDate = dailyRecords.first?.date {
                    state.scrollPosition = Calendar.current.startOfDay(for: firstDate)
                }
                if let firstDate = dailyRecords.first?.date {
                    state.earliestFetchedDate = Calendar.current.startOfDay(for: firstDate)
                }
                state.selectedDate = dailyRecords.last?.date
                state.selectedRecord = dailyRecords.last
            case .view(.tapSymbol(let date)):
                state.selectedDate = date
                state.selectedRecord = state.dailyRecords.first(where: { $0.date == date })
                
            case .view(.loadMoreBefore(let referenceDate)):
                state.isAppendingPastData = true
                // 차트의 scrollPosition은 '보이는 X 도메인의 선두(leading) 값'으로 동작함.
                // prepend(과거 주 추가) 후에도 동일한 화면을 유지하려면
                // 선두 값을 '기존 선두 + 7일'로 보정해야 점프가 사라진다.
                let oldLeading = state.scrollPosition
                
                // 현재 우리가 가진 가장 과거의 주를 기준으로, 그 이전 주만 1회 확장
                let cal = Calendar.current
                
                // 우리가 가진 가장 과거 날짜가 속한 '주'의 시작(로케일 안전)
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
                
                // 2) 추가할 구간 계산 (하한선과 겹치는 부분만 잘라서 포함)
                let daysToAppend: [Date] = (0..<7).compactMap { offset in
                    guard let day = cal.date(byAdding: .day, value: offset, to: previousWeekStart) else { return nil }
                    return day >= state.lowerBoundDate ? cal.startOfDay(for: day) : nil
                }
                
                // 하한선 넘어 완전히 벗어나면 중단
                guard !daysToAppend.isEmpty else {
                    return .send(.endAppending)
                }
                
                return .run { [dailyRecords = state.dailyRecords, oldLeading, daysToAppend] send in
                    var newRecords: [DailyRecord] = []
                    for date in daysToAppend {
                        let count = try await drawingData.fetchDrawings(date: date)?.count ?? 0
                        newRecords.append(.init(date: date, count: count))
                    }
                    // 데이터 prepend
                    await send(.setDailyRecords(newRecords + dailyRecords))
                    // 2) 스크롤 선두 복원(점프 방지): 기존 선두 + 7일
                    let cal = Calendar.current
                    let appendedDays = daysToAppend.count
                    let compensated = cal.date(byAdding: .day, value: appendedDays, to: oldLeading) ?? oldLeading
                    await send(.binding(.set(\.scrollPosition, compensated)))
                    
                    // 3) 페이징 종료
                    await send(.endAppending)
                }
            case .endAppending:
                state.isAppendingPastData = false
            default: break
            }
            return .none
        }
    }
    
    
    private func isDifferentDay(_ lhs: Date, _ rhs: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: lhs) != calendar.startOfDay(for: rhs)
    }
}
