//
//  DrawingChartAreaFeature.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI

import ComposableArchitecture


@Reducer
public struct DrawingChartAreaFeature {

    @ObservableState
    public struct State {
        var chartPagerState: DrawingChartPagerFeature.State = .initialState

        var calendal = Calendar.autoupdatingCurrent
        
        /// 현재 선택 데이터
        var rawSelection: Date? = nil
        /// 현재 스크롤 여부
        var isScrolling: Bool = false
        /// 현재 width값
        var chartWidth: CGFloat = 0
        /// y축 scale
        var yScale: ClosedRange<Int> = 0 ... 0
        /// y축 값
        var yValues: [Int] = []
        /// y축 계산을 위한 cancellable task
        var ySacleTask: Task<Bool, Error>?
        /// y축 변화시 보여줄 애니메이션
        var animation: Animation? = nil
        let visiblePageIndex = 1
        /// grouping 설정에 따라 그룹화 된, 차트에 표시할 준비가 된 데이터 항목
        var entries = ChartDataCollection()
        /// 현재 페이지
        var visiblePage: ChartDataPage {
            chartPagerState.chartPageState[visiblePageIndex].page
        }
        /// 표현할 데이터 그룹(날짜 단위)
        var grouping: ChartGrouping = .weekly
        
        /// 선택 데이터 정보
        var selection: GroupedChartDataEntry? {
            guard let selection = rawSelection else { return nil }
            let key = grouping.keyDate(selection)
            return entries.first { $0.date == key }
        }
  
        
        public static var initialState = Self()
    }
    
    public enum Action: BindableAction, ViewAction {
        case binding(BindingAction<State>)
        case view(View)
        case scope(ScopeAction)
        
        public enum View {
            case setChartWidth(CGFloat)
        }
        
        @CasePathable
        public enum ScopeAction {
            case chartPagerAction(DrawingChartPagerFeature.Action)
        }
    }
    
    
   public var body: some Reducer<State, Action> {
       BindingReducer()
       
       Scope(state:\.chartPagerState, action: \.scope.chartPagerAction) {
           DrawingChartPagerFeature()
       }
       
       Reduce { state, action in
           switch action {
           case .view(.setChartWidth(let width)):
               state.chartWidth = width
           default: break
               
           }
           return .none
       }
    }
}
