//
//  DrawingChartPageView.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI

import ComposableArchitecture

struct DrawingChartPageView: View {
    @Bindable public var store = Store(initialState: .initialState) {
        DrawingChartPageFeature()
    }
    
    var body: some View {
        Chart {
            ForEach(store.entries) { entry in
                BarMark(
                    x: .value("날짜", entry.date),
                    y: .value("절 수", entry.count)
                )
            }
        }
        .chartPlotStyle { content in
            content.clipped()
        }
        .chartXSelection(value: $store.rawSelection)
        .chartYScale(domain: store.yScale)
        .chartYAxis(.hidden)
        .chartXScale(domain: store.page.xScale)
        .chartXAxis {
            AxisMarks(values: .stride(by: store.grouping.xValueUnit, count: 1)) { value in
                if let dateValue = value.as(Date.self) {
                    if store.grouping.isAxisLimitMArk(dateValue) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1.3))
                            .foregroundStyle(.secondary.opacity(0.5))
                        
                        if store.grouping.isAxisMark(dateValue) {
                            AxisTick()
                            AxisValueLabel {
                                Text(store.xAxisValueLabel)
                            }
                        }
                    } else {
                        if store.grouping.isAxisMark(dateValue) {
                            AxisGridLine(stroke: StrokeStyle(dash: [1, 3]))
                                .foregroundStyle(.secondary.opacity(0.25))
                            
                            AxisTick()
                            
                            AxisValueLabel {
                                Text(store.xAxisValueLabel)
                            }
                        }
                    }
                }
            }
        }
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { value in
                proxy.selectXValue(at: value.location.x)
                
            }
        }
        .chartLegend(.hidden)
    }
}



