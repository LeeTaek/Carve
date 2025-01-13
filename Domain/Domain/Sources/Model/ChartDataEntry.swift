//
//  ChartDataEntry.swift
//  Domain
//
//  Created by 이택성 on 1/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct ChartDataEntry: Identifiable {
    public let id = UUID()
    public let date: Date
    public let count: Int
    
    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }
}
