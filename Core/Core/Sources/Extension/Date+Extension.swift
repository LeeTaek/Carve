//
//  Date+Extension.swift
//  Core
//
//  Created by 이택성 on 1/16/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public extension Date {
    func toLocalTime() -> Date {
        let timeZone = TimeZone.current
        let seconds = TimeInterval(timeZone.secondsFromGMT(for: self))
        return self.addingTimeInterval(seconds)
    }
}
