//
//  Calendar+Extension.swift
//  UIComponents
//
//  Created by 이택성 on 8/29/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

extension Calendar {
    /// 주어진 날짜로부터 시간 반환
    func startOfHour(for date: Date) -> Date {
        self.date(from: self.dateComponents([.year, .month, .day, .hour], from: date))!
    }
    
    /// 주어진 날짜로부터 그 주의 첫날 반환
    func startOfWeek(for date: Date) -> Date {
        self.startOfDay(for: self.date(from: dateComponents([.weekOfYear, .yearForWeekOfYear], from: date))!)
    }
    
    /// 주어진 날짜로부터 그 달의 첫날 반환
    func startOfMonth(for date: Date) -> Date {
        self.startOfDay(for: self.date(from: dateComponents([.month, .year], from: date))!)
    }
    
    /// 주어진 날짜로부터 시간 반환
    func endOfDay(for date: Date) -> Date {
        self.date(byAdding: DateComponents(day: 1, second: -1), to: self.startOfDay(for: date))!
    }
    
    /// 주어진 날짜로부터 그 주의 마지막 날 반환
    func endOfWeek(for date: Date) -> Date {
        self.endOfDay(
            for: self.date(byAdding: DateComponents(day: 6), to: self.startOfWeek(for: date))!)
    }
    
    /// 주어진 날짜로부터 그 달의 마지막 날 반환
    func endOfMonth(for date: Date) -> Date {
        self.endOfDay(
            for: self.date(byAdding: DateComponents(month: 1, day: -1), to: self.startOfMonth(for: date))!)
    }
    
}
