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
        public var chapterPercentages: [BibleChapter: Double] = [:]
        public var animatedPercentages: [BibleChapter: Double] = [:]
        
        public var isChartDataLoaded: Bool = false
        public var isChapterPercentageLoaded: Bool = false
        public var loadingProgress: Double = 0.0
        public var isLoading: Bool {
            !(isChartDataLoaded && isChapterPercentageLoaded)
        }
        
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
        case fetchChapterPercentage
        case setChapterPercentage([BibleChapter: Double])
        case updateLoadingProgress(Double)
        case updatePercentageAnimation(BibleChapter, Double)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.dismiss):
                state.isChartDataLoaded = false
                state.isChapterPercentageLoaded = false
                state.loadingProgress = 0.0
            case .inner(.fetchChartData):
                state.isChartDataLoaded = false
                return .run { send in
                    let groupedData = try await database.fetchGrouptedByDate()
                    let lastweek = calculateLastWeek()
                    let sortedData = groupedData.map { (key, value) -> ChartDataEntry in
                        let adjustedDate = Calendar.current.date(byAdding: .day, value: -1, to: key) ?? key
                        return ChartDataEntry(date: Calendar.current.startOfDay(for: adjustedDate), count: value)
                    }.sorted(by: { $0.date < $1.date })
                    
                    let adjustedData = stride(from: lastweek.lowerBound,
                                              to: lastweek.upperBound.addingTimeInterval(1),
                                              by: 60 * 60 * 24)
                        .map { date in
                            sortedData.first {
                                Calendar.current.isDate($0.date, equalTo: date, toGranularity: .day)
                            } ?? ChartDataEntry(date: date, count: 0)
                        }
                    await send(.inner(.setChartData(adjustedData)))
                }
            case .inner(.setChartData(let data)):
                state.chartData = data
                state.maxY = calculateRoundedMax(for: data)
                state.totalVerse = calculateTotalVerse(for: data)
                state.isChartDataLoaded = true
                if state.isChartDataLoaded && state.isChapterPercentageLoaded {
                    return .run { send in
                        await send(.inner(.loadingComplete))
                    }
                }
            case .inner(.fetchChapterPercentage):
                state.isChapterPercentageLoaded = false
                return .run { send in
                    let percentages = try await database.fetchAllChapterPercentage { progress in
                        Task { @MainActor in
                            send(.inner(.updateLoadingProgress(progress)))
                        }
                    }
                    await send(.inner(.setChapterPercentage(percentages)))
                }
            case .inner(.setChapterPercentage(let percentages)):
                state.chapterPercentages = percentages
                state.isChapterPercentageLoaded = true
                if state.isChartDataLoaded && state.isChapterPercentageLoaded {
                    return .run { send in
                        await send(.inner(.loadingComplete))
                    }
                }
            case .inner(.updateLoadingProgress(let progress)):
                state.loadingProgress = progress
            case .inner(.loadingComplete):
                withAnimation(.easeInOut(duration: 0.5)) {
                    state.isChartDataLoaded = true
                    state.isChapterPercentageLoaded = true
                }
            case .inner(.updatePercentageAnimation(let chapter, let percentage)):
                withAnimation(.easeInOut(duration: 1.0)) {
                    state.animatedPercentages[chapter] = percentage / 100.0
                }
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
