//
//  UIComponentsExtensionTesting.swift
//  UIComponentsTests
//
//  Created by Codex on 5/22/26.
//

import Foundation
import Testing

@testable import UIComponents

struct UIComponentsExtensionTesting {
    @Test("범위를 벗어난 비교 가능 값은 닫힌 범위 안으로 제한된다")
    func comparableValueClampsToClosedRange() {
        #expect((-1).clamped(to: 0...10) == 0)
        #expect(4.clamped(to: 0...10) == 4)
        #expect(12.clamped(to: 0...10) == 10)
    }

    @Test("달력 경계 계산은 날짜의 시간 구성요소를 제거한다")
    func calendarStartsRemoveSmallerDateComponents() {
        let calendar = makeCalendar()
        let date = makeDate(calendar: calendar, year: 2026, month: 5, day: 22, hour: 13, minute: 47, second: 31)

        #expect(calendar.startOfHour(for: date) == makeDate(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 22,
            hour: 13
        ))
        #expect(calendar.startOfMonth(for: date) == makeDate(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 1
        ))
    }

    @Test("달력 종료 경계 계산은 해당 기간의 마지막 초를 반환한다")
    func calendarEndsUseLastSecondOfPeriod() {
        let calendar = makeCalendar()
        let date = makeDate(calendar: calendar, year: 2024, month: 2, day: 14, hour: 8)

        #expect(calendar.endOfDay(for: date) == makeDate(
            calendar: calendar,
            year: 2024,
            month: 2,
            day: 14,
            hour: 23,
            minute: 59,
            second: 59
        ))
        #expect(calendar.endOfMonth(for: date) == makeDate(
            calendar: calendar,
            year: 2024,
            month: 2,
            day: 29,
            hour: 23,
            minute: 59,
            second: 59
        ))
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }
}
