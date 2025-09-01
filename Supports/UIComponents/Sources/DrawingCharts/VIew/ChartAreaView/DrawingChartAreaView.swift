//
//  DrawingChartAreaView.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI

import ComposableArchitecture

@ViewAction(for: DrawingChartAreaFeature.self)
public struct DrawingChartAreaView: View {
    @Bindable public var store: StoreOf<DrawingChartAreaFeature>
    
    public init(store: StoreOf<DrawingChartAreaFeature>) {
        self.store = store
    }
    
    public var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading) {
                if store.selection != nil {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: proxy.size.height * 0.2)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        AverageView(grouping: store.grouping, page: store.visiblePage)
                        .frame(height: proxy.size.height * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Chart {
                    if let selection = store.selection {
                        RuleMark(
                            x: .value("label.date", selection.date)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .zIndex(-1)
                        .annotation(
                            position: .top,
                            spacing: 0,
                            overflowResolution: .init(x: .fit(to: .plot), y: .disabled)
                        ) {
                            AnnotationView(entry: store.selection, grouping: store.grouping)
                        }
                    }
                }
                .chartYScale(domain: store.yScale)
                .chartYAxis {
                    AxisMarks(values: store.yValues) { value in
                        
                        AxisValueLabel {
                            Text("\(String(describing: value.as(Int.self))) 절")
                                .foregroundStyle(Color.secondary)
                        }
                        
                        AxisGridLine()
                    }
                }
                .chartXScale(domain: store.visiblePage.xScale)
                .chartXAxis {
                    AxisMarks(values: .stride(by: store.grouping.xValueUnit, count: 1)) { value in
                        
                        AxisValueLabel {
                            
                            Text(xAxisValueLabel(value.as(Date.self)))
                                .foregroundStyle(Color.clear)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartPlotStyle { content in
                    content
                        .background {
                            GeometryReader { plotAreaProxy in
                                Color.clear.preference(key: PlotAreSizePreferenceKey.self, value: plotAreaProxy.size )
                            }
                        }
                }
                .onAppear {
                    send(.setChartWidth(proxy.size.width * 0.9))
                }
                .onPreferenceChange(PlotAreSizePreferenceKey.self) { size in
                    send(.setChartWidth(min(size.width, proxy.size.width)))
                }
            }
        }
    }
    
    
    private func xAxisValueLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        switch store.grouping {
            case .daily:
                formatter.dateFormat = "HH"
            case .weekly:
                formatter.dateFormat = "EE"
            case .monthly:
                formatter.dateFormat = "dd"
        }
        
        return formatter.string(from: date)
    }
}



/// A `PreferenceKey` for aggregating `CGSize` values to determine the maximum plot area size within a chart.
///
fileprivate struct PlotAreSizePreferenceKey: PreferenceKey {
    
    /// The data type used by the preference key
    typealias Value = CGSize
    
    /// The default value for the preference key
    static var defaultValue: Value = .zero
    
    /// Combines multiple `CGSize` values into a single value by storing the maximum width and height encountered.
    /// - Parameters:
    ///   - value: A reference to the current maximum `CGSize` value.
    ///   - nextValue: A closure that returns the next `CGSize` value to be considered.
    ///
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        
        value = CGSize(
            width: max(value.width, nextValue().width),
            height: max(value.height, nextValue().height))
    }
}

