//
//  DailyRecordChartStateTesting.swift
//  ChartFeatureTests
//
//  Created by Codex on 9/12/26.
//

@testable import ChartFeature
import Foundation
import Testing
import ComposableArchitecture

struct DailyRecordChartStateTesting {
    @Test("가장 오래된 주에서 큰 드래그도 짧은 반동 후 같은 주와 Y축으로 복귀한다")
    @MainActor
    func oldestWeekBouncesWithoutPaging() async {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -27, to: today)!
        let lower = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        var state = DailyRecordChartFeature.State(lowerBoundDate: lower, scrollPosition: start)
        state.pageWidth = 600
        state.yScale = 0...20
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.view(.dragChanged(translationX: 1_000)))

        #expect(store.state.dragX > 0 && store.state.dragX < 32)
        #expect(store.state.scrollPosition == start)
        #expect(store.state.yScale == 0...20)

        await store.send(.commitMove(.prev))

        #expect(store.state.dragX == 0)
        #expect(!store.state.isPaging)
        #expect(!store.state.isScrolling)
        #expect(store.state.scrollPosition == start)
        #expect(store.state.yScale == 0...20)
    }

    @Test("0절 자리만 있으면 기록 없음으로 판단한다")
    func zeroCountPlaceholdersAreEmpty() {
        let start = chartTestDate(year: 2026, month: 9, day: 4)
        var state = DailyRecordChartFeature.State(
            records: (0..<7).map { DailyRecord(date: start.addingTimeInterval(Double($0) * 86_400), count: 0) },
            lowerBoundDate: start,
            scrollPosition: start
        )

        #expect(!state.hasWrittenRecord)

        state.records[2].count = 1

        #expect(state.hasWrittenRecord)
    }

    @Test("주간 접근성 요약은 합계 평균 최고일 기록 없는 날을 한 문장으로 제공한다")
    func accessibilitySummaryDescribesVisibleWeek() {
        let start = chartTestDate(year: 2026, month: 9, day: 4)
        let counts = [0, 2, 3, 0, 1, 3, 3]
        let records = counts.enumerated().map { offset, count in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            return DailyRecord(date: date, count: count)
        }
        let state = DailyRecordChartFeature.State(
            records: records,
            lowerBoundDate: start,
            scrollPosition: start
        )

        #expect(state.accessibilitySummary.contains("9월 4일부터 9월 10일까지"))
        #expect(state.accessibilitySummary.contains("모두 12절, 하루 평균 1.7절"))
        #expect(state.accessibilitySummary.contains("가장 많은 날은 9월 6일 3절"))
        #expect(state.accessibilitySummary.contains("없는 날은 이틀"))
    }
}

private func chartTestDate(year: Int, month: Int, day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
