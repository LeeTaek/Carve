//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Domain
import Foundation

import ComposableArchitecture

@Reducer
public struct DrewLogReducer {
    @ObservableState
    public struct State {
        public var chartData: [ChartDataEntry] = []
        public var totalSection: Int = 0
        public var maxY: Int = 0
        public var lastweek: [Date] = []
        
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
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .inner(.fetchChartData):
                return .run { send in
                    let groupedData = try await database.fetchGrouptedByDate()
                    let sortedData = groupedData.map {
                        ChartDataEntry(date: Calendar.current.startOfDay(for: $0.key), count: $0.value)
                    }.sorted(by: { $0.date < $1.date })
                    
                    let adjustedData = calculateLastWeek().map { date in
                        sortedData.first(where: {
                            Calendar.current.isDate($0.date, equalTo: date, toGranularity: .day)
                        }) ?? ChartDataEntry(date: date, count: 0)
                    }
                    print(adjustedData)
                    await send(.inner(.setChartData(adjustedData)))
                }
            case .inner(.setChartData(let data)):
                state.chartData = data
                state.maxY = calculateRoundedMax(for: data)
                state.totalSection = calculateTotalsection(for: data)
                state.lastweek = calculateLastWeek()
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
    
    private func calculateTotalsection(for entries: [ChartDataEntry]) -> Int {
        if entries.isEmpty { return 0 }
        return entries.map { $0.count }.reduce(0, +)
    }
    
    private func calculateLastWeek() -> [Date] {
        let localDate = Date().toLocalTime() // 로컬 시간대로 변환
        let today = Calendar.current.startOfDay(for: localDate)
        return (0...6).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }.reversed()
    }
}
