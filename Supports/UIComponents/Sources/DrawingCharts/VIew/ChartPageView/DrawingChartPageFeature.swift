//
//  DrawingChartPageFeature.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import Foundation

import ComposableArchitecture

@Reducer
public struct DrawingChartPageFeature {
    @ObservableState
    public struct State: Identifiable {
        public let id: UUID = UUID()
        /// 현재 페이지
        var page: ChartDataPage
        /// 보여줄 차트의 날짜
        var pageDate: Date = .now
        /// 현재 선택 날짜
        var rawSelection: Date?
        /// grouping 설정에 따라 그룹화 된, 차트에 표시할 준비가 된 데이터 항목
        var entries = ChartDataCollection()
        /// 표현할 데이터 그룹(날짜 단위)
        var grouping: ChartGrouping = .weekly
        /// 선택 데이터 정보
        var selection: GroupedChartDataEntry? {
            guard let selection = rawSelection else { return nil }
            let key = grouping.keyDate(selection)
            return entries.first { $0.date == key }
        }
        /// Y축 값 범위
        var yScale: ClosedRange<Int> = 0 ... 0
        /// axisLabel format
        var xAxisValueLabel: String = ""
        
        public static var initialState = Self(.init())
        
        public init(_ page: ChartDataPage, rawSelection: Date?) {
            self.page = page
            self.rawSelection = rawSelection
        }
        
        public init(_ page: ChartDataPage) {
            self.page = page
            self.rawSelection = nil
        }
        
    }
    
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case update(ChartDataCollection?)
    }
    
   public var body: some Reducer<State, Action> {
       BindingReducer()
//           .onChange(of: \.page) { _, _ in
//               Reduce { _, _ in
//                   return .send(.update(nil))
//               }
//           }
       
       Reduce { state, action in
           switch action {
           case .update(let collection):
               if let collection {
                   state.entries = collection
               }
               let data = state.entries
               
               let clampedPageDate = state.pageDate.clamped(to: data.dateRange)
               state.pageDate = state.grouping.pageDate(for: clampedPageDate)
               
               let lowerBound = state.grouping.nextPageDate(for: state.pageDate, offset: -3)
               let upperBound = state.grouping.nextPageDate(for: state.pageDate, offset: 4)
               
               state.entries = group(state.entries, grouping: state.grouping, range: lowerBound...upperBound)
               state.yScale = yScale(for: state.entries)
               let yValue = self.yValue(for: state.yScale)
               
               for i in -1...1 {
                   let index = i+1
                   let date = state.grouping.nextPageDate(for: state.pageDate, offset: i)
                   let xScale = xScale(for: state.pageDate, grouping: state.grouping)
               }
               
           default: break
           }
           return .none
       }
    }
}


extension DrawingChartPageFeature {
    /// grouping 속성에 따라 지정된 범위 안의 측정 항목들을 그룹화
    private func group(
        _ source: ChartDataCollection,
        grouping: ChartGrouping,
        range: ClosedRange<Date>? = nil
    ) -> ChartDataCollection {
        
        var groups: [Date: GroupedChartDataEntry] = [:]
        
        source.forEach { entry in
            if let range, !range.contains(entry.date){
                return
            }
            
            let date = grouping.keyDate(entry.date)
            
            if var group = groups[date] {
                group.insert(entry.value)
                groups[date] = group
            } else {
                groups[date] = GroupedChartDataEntry(date: date, entry.value)
            }
        }
        return .init(contentOf: groups.values)
    }
    
    /// entries 기반으로 y축 스케일 계산
    /// - Parameters:
    ///   - entries: 데이터
    ///   - allowNavigateValues: 음수값 허용 여부
    /// - Returns: y축 범위
    private func yScale(
        for entries: ChartDataCollection,
        allowNavigateValues: Bool = false
    ) -> ClosedRange<Int> {
        let minValue = Double(entries.min ?? 0)
        let maxValue = Double(entries.max ?? 0)

        let baseMin = allowNavigateValues ? minValue : min(0, minValue)
        let baseMax = allowNavigateValues ? maxValue : max(0, maxValue)

        let lowerBound = Int((Double(baseMin) - abs(Double(baseMin)) * 0.25).rounded(.down))
        let upperBound = Int((Double(baseMax) + abs(Double(baseMax)) * 0.25).rounded(.up))

        if lowerBound == upperBound {
            return (lowerBound - 1)...(upperBound + 1)
        }
        return lowerBound...upperBound
    }
    
    
    /// 지정된 스케일 안에서 y축 라벨 값 집합 생성
    private func yValue(for yScale: ClosedRange<Int>) -> [Int] {
        let min = yScale.lowerBound
        let max = yScale.upperBound
        
        let range = max - min
        
        let firstThird = min + range / 3
        let secondThird = min + 2 * range / 3

        return [min, firstThird, secondThird, max]
    }
    
    private func xScale(for date: Date, grouping: ChartGrouping) -> ClosedRange<Date> {
        let calendar = Calendar.autoupdatingCurrent
        var lowerBound: Date
        var upperBound: Date
        
        switch grouping {
        case .daily:
            lowerBound = calendar.startOfDay(for: date)
            upperBound = calendar.endOfDay(for: date)
            
        case .weekly:
            lowerBound = calendar.startOfWeek(for: date)
            upperBound = calendar.endOfWeek(for: date)
            
        case .monthly:
            lowerBound = calendar.startOfMonth(for: date)
            upperBound = calendar.endOfMonth(for: date)
        }
        
        return lowerBound...upperBound
    }
}
