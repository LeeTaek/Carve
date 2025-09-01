//
//  ChartDataCollection.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public final class ChartDataCollection: RandomAccessCollection, Equatable {
    
    private var data: [GroupedChartDataEntry] = []
    
    public var startIndex: Int {
        data.startIndex
    }
    
    public var endIndex: Int {
        data.endIndex
    }
    
    public var isEmpty: Bool {
        data.isEmpty
    }
    
    /// Chart Data Entries의 날짜 범위
    public var dateRange: ClosedRange<Date> = .now ... .now
    
    /// 표현할 Chart Data Entries의 범위
    public var valueRange: ClosedRange<Int> = 0 ... 0
    
    
    /// 초기화 (빈값)
    public init() {
        let now = Date.now
        
        self.data = []
        self.dateRange = now ... now
        self.valueRange = 0 ... 0
    }
    
    public init<S: Sequence>(contentOf sequence: S) where S.Element == GroupedChartDataEntry {
        let now = Date.now
        
        self.data = sequence.sorted { $0.date <= $1.date }
        
        if let first = data.first?.date, let last = data.last?.date {
            self.dateRange = first ... last
        } else {
            self.dateRange = now ... now
        }
        
        if let min = data.min, let max = data.max {
            self.valueRange = min ... max
        } else {
            self.valueRange = 0 ... 0
        }
        
    }
    
    
    public subscript(_ index: Int) -> GroupedChartDataEntry {
        get { data[index] }
    }
    
    public static func ==(lhs: ChartDataCollection, rhs: ChartDataCollection) -> Bool {
        lhs.data == rhs.data
    }
}
