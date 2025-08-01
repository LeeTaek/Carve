//
//  DrawingChartFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

public struct DailyRecord: Equatable {
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
    }
    
    @Dependency(\.drawingData) var drawingData
    
    public enum Action: ViewAction {
        case view(View)
        case setDailyRecords([DailyRecord])
        
        public enum View {
            case fetchData
            
        }
    }
    
    public var body: some Reducer<State, Action> {
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
            }
            return .none
        }
    }
}
