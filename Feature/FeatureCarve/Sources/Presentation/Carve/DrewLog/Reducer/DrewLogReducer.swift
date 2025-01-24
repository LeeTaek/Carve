//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct DrewLogReducer {
    @ObservableState
    public struct State {
        public var chartData: [ChartDataEntry] = []
        public var totalVerse: Int = 0
        public var maxY: Int = 0
        public var isLoading: Bool = true
        
        public static let initialState = State()
    }
    @Dependency(\.drawingData) var database
    
    public enum Action: FeatureAction {
        case view(ViewAction)
        case inner(InnerAction)
    }
    public enum ViewAction {
        case dismiss
    }
    
    public enum InnerAction {
        case fetchChartData
        case setChartData([ChartDataEntry])
        case loadingComplete
        case chapterPercentage
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.dismiss):
                state.isLoading = true
            case .inner(.fetchChartData):
                state.isLoading = true
                return .run { send in
                    let groupedData = try await database.fetchGrouptedByDate()
                    let lastweek = calculateLastWeek()
                    let sortedData = groupedData.map {
                        let adjustedDate = Calendar.current.date(byAdding: .day, value: -1, to: $0.key) ?? $0.key
                        return ChartDataEntry(date: Calendar.current.startOfDay(for: adjustedDate), count: $0.value)
                    }.sorted(by: { $0.date < $1.date })
                    
                    let adjustedData = stride(from: lastweek.lowerBound,
                                              to: lastweek.upperBound.addingTimeInterval(1),
                                              by: 60 * 60 * 24)
                        .map { date in
                            sortedData.first {
                                Calendar.current.isDate($0.date, equalTo: date, toGranularity: .day)
                            } ?? ChartDataEntry(date: date, count: 0)
                        }
                    await send(.inner(.loadingComplete))
                    await send(.inner(.setChartData(adjustedData)))
                }
            case .inner(.setChartData(let data)):
                state.chartData = data
                state.maxY = calculateRoundedMax(for: data)
                state.totalVerse = calculateTotalVerse(for: data)
            case .inner(.loadingComplete):
                withAnimation(.easeInOut(duration: 0.5)) { // 애니메이션 추가
                    state.isLoading = false
                }
            default: break
            }
            return .none
        }
    }
    
    private func calculateRoundedMax(for entries: [ChartDataEntry]) -> Int {
        guard let maxCount = entries.map({ $0.count }).max() else { return 10 }
        let roundedMax = Double(maxCount) / 10.0
        return Int(ceil(roundedMax) * 10)
    }
    
    private func calculateTotalVerse(for entries: [ChartDataEntry]) -> Int {
        if entries.isEmpty { return 0 }
        return entries.map { $0.count }.reduce(0, +)
    }
        
    private func calculateLastWeek() -> ClosedRange<Date> {
        let localDate = Date().toLocalTime()
        let today = Calendar.current.startOfDay(for: localDate)
        guard let startDate = Calendar.current.date(byAdding: .day, value: -7, to: today),
              let endDate = Calendar.current.date(byAdding: .day, value: -1, to: today)
        else {
            return today...today
        }
        return startDate...endDate
    }
}
