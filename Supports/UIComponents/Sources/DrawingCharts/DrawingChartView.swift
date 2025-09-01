//
//  DrawingChartView.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: DrawingChartFeature.self)
public struct DrawingChartView: View {
    @Bindable public var store: StoreOf<DrawingChartFeature>
    
    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
            segmentView()
            
            chartArea()
        }
        .onAppear {
            
        }
    }
    
    @ViewBuilder
    func segmentView() -> some View {
        if store.isGroupingPickerVisible, !store.data.isEmpty {
            Picker("label.show-all", selection: $store.grouping) {
                ForEach(ChartGrouping.allCases, id: \.self) {
                    Text($0.string)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top)
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    func chartArea() -> some View {
        if store.data.isEmpty {
            ContentUnavailableView("label.no-data", systemImage: "circle.slash")
                .transition(.opacity)
        } else {
            DrawingChartAreaView(
                store: store.scope(state: \.chartAreaState,
                                   action: \.scope.chartAreaAction)
            )
        }
    }
    
}
