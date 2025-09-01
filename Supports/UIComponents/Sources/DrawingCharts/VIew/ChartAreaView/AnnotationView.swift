//
//  AnnotaionView.swift
//  UIComponents
//
//  Created by 이택성 on 8/29/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

public struct AnnotationView: View {
    let entry: GroupedChartDataEntry?
    let dateFormatter: DateFormatter
    
    public init(entry: GroupedChartDataEntry?, grouping: ChartGrouping) {
        let formatter = DateFormatter()
        self.entry = entry
        switch grouping {
        case .daily:
            formatter.dateFormat = "dd MMM yyyy, hh:mm"
        case .weekly, .monthly:
            formatter.dateFormat = "dd MMM yyyy"
        }
        self.dateFormatter = formatter
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
            if let entry, entry.count > 1 {
                Text("label.average")
                    .textCase(.uppercase)
                    .font(.caption.weight(.light))
                    .foregroundStyle(Color.secondary)
                
                HStack(alignment: .firstTextBaseline) {
                    Text("\(entry.value)")
                    Text("절")
                        .textCase(.uppercase)
                        .font(.callout.smallCaps())
                        .foregroundStyle(Color.secondary)
                }
                .textFieldStyle(.roundedBorder)
                .font(.title)
                .monospacedDigit()
                
                Text(entry.date, formatter: dateFormatter)
                    .font(.caption.weight(.light))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
