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

    @Test("하루 평균은 소수점 한 자리로 표시한다")
    func weekAverageTextUsesOneFractionDigit() {
        let start = makeDate(year: 2026, month: 9, day: 4)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.dailyRecords = [
            DailyRecord(date: start, count: 2),
            DailyRecord(date: start.addingTimeInterval(86_400), count: 3),
            DailyRecord(date: start.addingTimeInterval(86_400 * 2), count: 7)
        ]

        #expect(state.weekAverageText == "1.7")
    }

    @Test("현재 주의 일별 권별 횟수를 합산해 가장 많이 필사한 권을 반환한다")
    func topChapterMergesCountsWithinVisibleWeekOnly() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)
        let psalms = BibleChapter(title: .psalms, chapter: 23)

        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        // 창세기 5 vs 요한복음 4 → 동점이 아니므로 tie-break와 무관하게 창세기가 1위.
        // 시편 20은 현재 주(5/18~5/24) 밖이라 합산에서 제외되어야 한다.
        state.chapterCountsByDay = [
            start: [genesis: 2, john: 1],
            makeDate(year: 2026, month: 5, day: 20): [john: 3],
            makeDate(year: 2026, month: 5, day: 24): [genesis: 3],
            makeDate(year: 2026, month: 5, day: 25): [psalms: 20]
        ]

        #expect(state.topChapter?.chapter == genesis)
        #expect(state.topChapter?.count == 5)
    }

    @Test("합계가 동점이면 성경 순서가 앞선 권을 반환한다")
    func topChapterBreaksTieByBibleOrder() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)

        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        // 창세기 2+3=5, 요한복음 1+4=5 로 동점.
        state.chapterCountsByDay = [
            start: [genesis: 2, john: 1],
            makeDate(year: 2026, month: 5, day: 20): [john: 4],
            makeDate(year: 2026, month: 5, day: 24): [genesis: 3]
        ]

        // 성경 순서(BibleTitle.allCases)상 창세기가 요한복음보다 앞서므로 창세기가 선택된다.
        #expect(state.topChapter?.chapter == genesis)
        #expect(state.topChapter?.count == 5)
    }

    @Test("같은 권 안에서 합계가 동점이면 장 번호가 작은 쪽을 반환한다")
    func topChapterBreaksTieByChapterNumber() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        let genesis1 = BibleChapter(title: .genesis, chapter: 1)
        let genesis5 = BibleChapter(title: .genesis, chapter: 5)

        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [
            start: [genesis5: 2, genesis1: 2],
            makeDate(year: 2026, month: 5, day: 21): [genesis5: 1, genesis1: 1]
        ]

        #expect(state.topChapter?.chapter == genesis1)
        #expect(state.topChapter?.count == 3)
    }

    @Test("동점인 권이 여러 개여도 Dictionary 삽입 순서와 무관하게 항상 같은 결과를 반환한다")
    func topChapterIsDeterministicRegardlessOfInsertionOrder() {
        let start = makeDate(year: 2026, month: 5, day: 18)
        let tiedChapters: [BibleChapter] = [
            BibleChapter(title: .john, chapter: 3),
            BibleChapter(title: .psalms, chapter: 23),
            BibleChapter(title: .genesis, chapter: 1),
            BibleChapter(title: .revelation, chapter: 22),
            BibleChapter(title: .exodus, chapter: 20)
        ]

        // 삽입 순서를 매번 섞어도(= Dictionary 순회 순서가 달라져도) 결과가 흔들리면 안 된다.
        for _ in 0..<50 {
            var counts: [BibleChapter: Int] = [:]
            for chapter in tiedChapters.shuffled() {
                counts[chapter] = 5
            }

            var state = DrawingWeeklySummaryFeature.State()
            state.scrollPosition = start
            state.chapterCountsByDay = [start: counts]

            #expect(state.topChapter?.chapter == BibleChapter(title: .genesis, chapter: 1))
            #expect(state.topChapter?.count == 5)
        }
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
