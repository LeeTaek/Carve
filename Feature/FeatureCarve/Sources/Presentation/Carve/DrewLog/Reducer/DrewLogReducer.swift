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
        case loadDrawing(Date)
        case setPreviewValue
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .inner(.fetchChartData):
                return .run { send in
                    let groupedData = try await database.fetchGrouptedByDate()
                    let sortedData = groupedData.map { ChartDataEntry(date: $0.key, count: $0.value) }
                        .sorted(by: { $0.date < $1.date })
                    await send(.inner(.setChartData(sortedData)))
                }
            case .inner(.setChartData(let data)):
                state.chartData = data
            case .inner(.setPreviewValue) :
                return .run { _ in
                    try await database.setDrawing(title: .initialState, to: 10)
                    for chapter in 1...10 {
                        let drawing = DrawingVO(
                            bibleTitle: .initialState,
                            section: chapter,
                            updatedDate: Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: chapter))
                        )
                        try await database.update(item: drawing)
                    }
                }

            default: break
            }
            return .none
        }
    }
    
    
}
