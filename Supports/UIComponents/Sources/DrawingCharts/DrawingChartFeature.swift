//
//  DrawingChartFeature.swift
//  UIComponents
//
//  Created by 이택성 on 8/29/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct DrawingChartFeature {
    @ObservableState
    public struct State {
        var chartAreaState: DrawingChartAreaFeature.State = .initialState
        
        var isGroupingPickerVisible: Bool = false
        var data: ChartDataCollection
        
        var grouping: ChartGrouping
    }
    
    public enum Action: BindableAction, ViewAction {
        case binding(BindingAction<State>)
        case view(View)
        case scope(ScopeAction)
        
        public enum View {
            
        }
        
        @CasePathable
        public enum ScopeAction {
            case chartAreaAction(DrawingChartAreaFeature.Action)
        }
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
        
        Scope(state: \.chartAreaState,
              action: \.scope.chartAreaAction) {
            DrawingChartAreaFeature()
        }
    }
}
