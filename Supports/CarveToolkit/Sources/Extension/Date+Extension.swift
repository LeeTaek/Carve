//
//  Date+Extension.swift
//  CarveToolkit
//
//  Created by 이택성 on 12/19/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public extension Date {
    /// 현재 날짜의 시작(00:00:00)으로 정렬.
    func alignToDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    /// `days`만큼 일(day)을 더한 날짜를 반환.
    func addDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// `hours`만큼 시간(hour)을 더한 날짜를 반환.
    func addHours(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    /// 하루의 정오(12:00)를 반환합니다.
    func middleOfDay() -> Date {
        self.alignToDay().addHours(12)
    }
}
