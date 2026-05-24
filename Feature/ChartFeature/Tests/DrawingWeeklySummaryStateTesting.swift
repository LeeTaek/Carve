//
//  DrawingWeeklySummaryStateTesting.swift
//  ChartFeatureTest
//
//  Created by Codex on 5/23/26.
//

@testable import ChartFeature
import Domain
import Foundation
import Testing

struct DrawingWeeklySummaryStateTesting {
    @Test("주간 합계와 최댓값은 현재 7일 범위의 기록만 사용한다")
    func weeklyCountsUseOnlyCurrentPageRecords() {
        let anchor = makeDate(year: 2026, month: 5, day: 18)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = anchor
        state.dailyRecords = [
            DailyRecord(date: anchor, count: 2),
            DailyRecord(date: day(after: 3, from: anchor), count: 5),
            DailyRecord(date: day(after: 6, from: anchor), count: 1),
            DailyRecord(date: day(after: -1, from: anchor), count: 100),
            DailyRecord(date: day(after: 7, from: anchor), count: 100)
        ]

        #expect(state.weekTotalCount == 8)
        #expect(state.weekMaxCount == 5)
    }

    @Test("주간 평균은 7일 기준으로 반올림한다")
    func weeklyAverageRoundsSevenDayTotal() {
        let anchor = makeDate(year: 2026, month: 5, day: 18)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = anchor
        state.dailyRecords = [
            DailyRecord(date: anchor, count: 3),
            DailyRecord(date: day(after: 1, from: anchor), count: 4),
            DailyRecord(date: day(after: 2, from: anchor), count: 4)
        ]

        #expect(state.weekTotalCount == 11)
        #expect(state.weekAverageCount == 2)
    }

    @Test("최다 필사 장은 현재 주간 범위의 장별 카운트만 합산한다")
    func topChapterAggregatesOnlyCurrentWeekCounts() {
        let anchor = makeDate(year: 2026, month: 5, day: 18)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)
        let psalms = BibleChapter(title: .psalms, chapter: 23)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = anchor
        state.chapterCountsByDay = [
            anchor: [genesis: 2, john: 1],
            day(after: 2, from: anchor): [john: 3],
            day(after: 7, from: anchor): [psalms: 20]
        ]

        #expect(state.topChapter?.chapter == john)
        #expect(state.topChapter?.count == 4)
    }

    @Test("현재 주간 범위에 장별 카운트가 없으면 최다 장은 없다")
    func topChapterIsNilWhenCurrentWeekHasNoCounts() {
        let anchor = makeDate(year: 2026, month: 5, day: 18)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = anchor
        state.chapterCountsByDay = [
            day(after: -1, from: anchor): [BibleChapter(title: .genesis, chapter: 1): 3],
            day(after: 7, from: anchor): [BibleChapter(title: .john, chapter: 3): 4]
        ]

        #expect(state.topChapter == nil)
    }
}

private func makeDate(year: Int, month: Int, day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

private func day(after offset: Int, from date: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: date)!
}
