//
//  ChartDataEntry.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public protocol ChartDataEntry: Identifiable, Hashable, Equatable {
    /// 필사 날짜
    var date: Date { get }
    /// 필사한 구절 수
    var value: Int { get }
}

public extension ChartDataEntry {
    var doubleValue: Double { Double(value) }
}


public struct ChartDataPage: Equatable {
    /// 페이지 날짜
    var date: Date = .now
    /// Page X축 스케일
    var xScale: ClosedRange<Date> = .now ... .now
    /// 페이지의 entries의 평균
    var average: Int?
}

public struct GroupedChartDataEntry: ChartDataEntry {
    private var values: Set<Int>
    
    public let id = UUID()
    public let date: Date
    public var value: Int { average }
    
    public var count: Int {
        values.count
    }
    
    public var sum: Int {
        values.reduce(0, +)
    }
    
    public var average: Int {
        count > 0 ? sum / count : 0
    }
    
    public init(date: Date) {
        self.date = date
        self.values = []
    }
    
    public init (date: Date, _ values: Int) {
        self.date = date
        self.values = [values]
    }
    
    public mutating func insert(_ value: Int) {
        values.insert(value)
    }
    
    public mutating func insert<S: Sequence>(_ values: S) where S.Element == Int {
        self.values.formUnion(values)
    }
}



extension RandomAccessCollection where Element: ChartDataEntry {
    
    var min: Int? {
        compactMap { $0.value }.min()
    }
    
    var max: Int? {
        compactMap { $0.value }.max()
    }
    
    var sum: Int? {
        isEmpty ? 0 : map(\.value).reduce(0, +)
    }
    
    var average: Int? {
        guard let sum else { return nil }
        return isEmpty ? 0 : (sum / count)
    }
}
