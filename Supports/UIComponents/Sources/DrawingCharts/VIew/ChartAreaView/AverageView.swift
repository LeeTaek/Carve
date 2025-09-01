//
//  AverageView.swift
//  UIComponents
//
//  Created by 이택성 on 8/29/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct AverageView: View {
    /// 필사한 절 평균값
    var average: Int?
    /// 페이지에서 보일 날짜 계산
    var date: String
    
    public init(grouping: ChartGrouping, page: ChartDataPage) {
        self.date = grouping.dateFormatString(page: page)
    }
    
    public var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading) {
                Text("label.average")
                    .font(.caption.uppercaseSmallCaps())
                
                HStack(alignment: .firstTextBaseline) {
                    if let average, average != 0 {
                        Text("\(average)")
                            .fontWeight(.medium)
                        Text("절")
                            .textCase(.uppercase)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("label.no-data")
                    }
                }
                .font(.largeTitle.monospacedDigit())
            }
            
            HStack {
                Text(date)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
