//
//  DrawingWeeklySummaryStateTesting.swift
//  ChartFeatureTest
//
//  Created by Codex on 5/28/26.
//

@testable import ChartFeature
import Domain
import Foundation
import Testing

struct DrawingWeeklySummaryStateTesting {
    @Test("현재 주 범위에 포함된 기록만 합계, 평균, 최댓값에 반영한다")
    func currentWeekMetricsIgnoreRecordsOutsideVisibleWeek() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.dailyRecords = [
            DailyRecord(date: start.addingTimeInterval(60 * 60), count: 2),
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 21), count: 5),
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 24), count: 7),
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 25), count: 100),
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 17), count: 50)
        ]

        #expect(state.weekTotalCount == 14)
        #expect(state.weekAverageCount == 2)
        #expect(state.weekMaxCount == 7)
    }

    @Test("현재 주에 기록이 없으면 주간 지표를 0으로 반환한다")
    func emptyCurrentWeekReturnsZeroMetrics() {
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = makeDate(year: 2026, month: 5, day: 18)
        state.dailyRecords = [
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 17), count: 4),
            DailyRecord(date: makeDate(year: 2026, month: 5, day: 25), count: 9)
        ]

        #expect(state.weekTotalCount == 0)
        #expect(state.weekAverageCount == 0)
        #expect(state.weekMaxCount == 0)
    }

    @Test("현재 주의 일별 권별 횟수를 합산해 가장 많이 필사한 권을 반환한다")
    func topChapterMergesCountsWithinVisibleWeekOnly() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)
        let psalms = BibleChapter(title: .psalms, chapter: 23)

        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [
            start: [genesis: 2, john: 1],
            makeDate(year: 2026, month: 5, day: 20): [john: 4],
            makeDate(year: 2026, month: 5, day: 24): [genesis: 3],
            makeDate(year: 2026, month: 5, day: 25): [psalms: 20]
        ]

        #expect(state.topChapter?.chapter == genesis)
        #expect(state.topChapter?.count == 5)
    }
}

private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var calendar = Calendar.current
    calendar.timeZone = .current
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}
