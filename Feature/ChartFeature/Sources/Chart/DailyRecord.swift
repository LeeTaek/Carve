//
//  DailyRecord.swift
//  ChartFeature
//
//  Created by 이택성 on 12/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct DailyRecord: Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var count: Int
}
