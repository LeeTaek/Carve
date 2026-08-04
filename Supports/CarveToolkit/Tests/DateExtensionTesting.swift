//
//  DateExtensionTesting.swift
//  CarveToolkitTest
//
//  Created by Codex on 6/11/26.
//

@testable import CarveToolkit
import Foundation
import Testing

struct DateExtensionTesting {
    @Test("날짜 정렬은 같은 날의 시간을 자정으로 내린다")
    func alignToDayDropsTimeComponents() throws {
        let date = try #require(makeDate(year: 2026, month: 6, day: 11, hour: 18, minute: 42, second: 9))
        let aligned = date.alignToDay()

        #expect(aligned == makeDate(year: 2026, month: 6, day: 11))
    }

    @Test("일 단위 더하기는 월 경계를 넘어도 날짜를 유지한다")
    func addDaysCrossesMonthBoundary() throws {
        let date = try #require(makeDate(year: 2026, month: 1, day: 30, hour: 9))

        #expect(date.addDays(2) == makeDate(year: 2026, month: 2, day: 1, hour: 9))
        #expect(date.addDays(-30) == makeDate(year: 2025, month: 12, day: 31, hour: 9))
    }

    @Test("시간 단위 더하기는 일 경계를 넘어도 분과 초를 유지한다")
    func addHoursCrossesDayBoundary() throws {
        let date = try #require(makeDate(year: 2026, month: 6, day: 11, hour: 23, minute: 15, second: 30))

        #expect(date.addHours(2) == makeDate(year: 2026, month: 6, day: 12, hour: 1, minute: 15, second: 30))
        #expect(date.addHours(-24) == makeDate(year: 2026, month: 6, day: 10, hour: 23, minute: 15, second: 30))
    }

    @Test("정오 계산은 입력 시간과 무관하게 같은 날 12시를 반환한다")
    func middleOfDayReturnsNoonOfSameDay() throws {
        let date = try #require(makeDate(year: 2026, month: 6, day: 11, hour: 23, minute: 59, second: 59))

        #expect(date.middleOfDay() == makeDate(year: 2026, month: 6, day: 11, hour: 12))
    }
}

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0
) -> Date? {
    let calendar = Calendar.current

    return calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    )
}
