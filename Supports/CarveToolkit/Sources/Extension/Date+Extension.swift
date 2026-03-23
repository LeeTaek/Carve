//
//  Date+Extension.swift
//  CarveToolkit
//
//  Created by 이택성 on 12/19/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public extension Date {
    func alignToDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    func addDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func addHours(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    func middleOfDay() -> Date {
        self.alignToDay().addHours(12)
    }
}
