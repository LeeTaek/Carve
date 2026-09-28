//
//  DrawingChartLoadMoreTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/28/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 과거 주 추가 조회(`.view(.loadMoreBefore)`)의 조회 기간 · 하한 · 병합 경계.
/// 한 주 전체를 붙이는 정상 경로와 하한 도달 시 바로 끝나는 경로는 `DrawingChartFeatureTesting` 에 있다.
struct DrawingChartLoadMoreTesting {
    @Test("조회 기간은 가장 이른 날이 속한 주의 시작보다 7일 앞에서 시작하는 7일이다")
    @MainActor
    func loadMoreBeforeQueriesWeekBeforeEarliestWeekStart() async {
        // Given: 가장 이른 날이 주 중간(주 시작 + 3일)이다
        let calendar = Calendar.current
        let earliestWeekStart = calendar.dateInterval(of: .weekOfYear, for: fixedChartDay(-10))!.start
        let earliest = calendar.date(byAdding: .day, value: 3, to: earliestWeekStart)!
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: earliestWeekStart)!
        let repository = RangeRecordingActivityRepository()
        let store = TestStore(initialState: loadMoreState(earliest: earliest)) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = repository
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.loadMoreBefore(earliest)))
        await store.receive(\.setFetchedDailyData)
        await store.receive(\.dailyRecordChart)
        await store.receive(\.endAppending)

        // Then: 가장 이른 날 7일 전이 아니라, 그 주 시작의 7일 전부터 그 주 시작까지를 한 번 조회한다
        let ranges = await repository.receivedRanges
        #expect(ranges == [DateInterval(start: previousWeekStart, end: earliestWeekStart)])
        #expect(calendar.dateComponents([.day], from: previousWeekStart, to: earliestWeekStart).day == 7)
    }

    @Test("하한이 직전 주 중간이면 하한 이전 날은 빼고 붙인 날 수만큼만 보던 위치를 민다")
    @MainActor
    func loadMoreBeforeClipsDaysBeforeLowerBound() async {
        // Given: 하한이 직전 주 시작 + 3일, 하한 전날과 하한 다음날에 한 절씩
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: fixedChartDay(0))!.start
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let lowerBound = calendar.date(byAdding: .day, value: 3, to: previousWeekStart)!
        let beforeLowerBound = calendar.date(byAdding: .day, value: -1, to: lowerBound)!
        let afterLowerBound = calendar.date(byAdding: .day, value: 1, to: lowerBound)!
        let john = BibleChapter(title: .john, chapter: 3)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let repository = RangeRecordingActivityRepository(activities: [
            loadMoreActivity(beforeLowerBound.addingTimeInterval(3_600), genesis, verse: 1),
            loadMoreActivity(afterLowerBound.addingTimeInterval(3_600), john, verse: 16)
        ])
        let store = TestStore(initialState: loadMoreState(earliest: fixedChartDay(0), lowerBound: lowerBound)) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = repository
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let records = chartRecords(from: lowerBound, counts: [0, 1, 0, 0])

        // When
        await store.send(.view(.loadMoreBefore(fixedChartDay(0))))

        // Then: 하한부터 4일만 앞에 붙고, 하한 전날의 필사는 장별 횟수에도 들어가지 않는다
        await store.receive(\.setFetchedDailyData) {
            $0.dailyRecordChart.records = records
            $0.earliestFetchedDate = lowerBound
            for record in records {
                $0.chapterCountsByDay[record.date] = record.date == afterLowerBound ? [john: 1] : [:]
            }
        }
        #expect(store.state.chapterCountsByDay[beforeLowerBound] == nil)
        // Then: 보던 위치는 7일이 아니라 붙인 4일만큼 밀린다
        await store.receive(\.dailyRecordChart) {
            $0.dailyRecordChart.scrollPosition = fixedChartDay(4)
            $0.drawingWeeklySummary.scrollPosition = fixedChartDay(4)
        }
        await store.receive(\.endAppending)
    }

    @Test("장별 횟수는 기존 날짜 값을 그대로 두고 새로 붙인 날짜 값을 더한다")
    @MainActor
    func loadMoreBeforeMergesChapterCountsWithExisting() async {
        // Given: 어제 · 오늘 기록과 장별 횟수가 이미 있고, 직전 주 셋째 날에 요한복음 3장 두 절
        let calendar = Calendar.current
        let john = BibleChapter(title: .john, chapter: 3)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let existingRecords = chartRecords(from: fixedChartDay(-1), counts: [2, 1])
        let existingCounts: [Date: [BibleChapter: Int]] = [
            fixedChartDay(-1): [genesis: 2],
            fixedChartDay(0): [john: 1]
        ]
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: fixedChartDay(-1))!.start
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let thirdDay = calendar.date(byAdding: .day, value: 2, to: previousWeekStart)!
        var state = loadMoreState(earliest: fixedChartDay(-1))
        state.dailyRecordChart.records = existingRecords
        state.chapterCountsByDay = existingCounts
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RangeRecordingActivityRepository(activities: [
                loadMoreActivity(thirdDay.addingTimeInterval(3_600), john, verse: 16),
                loadMoreActivity(thirdDay.addingTimeInterval(7_200), john, verse: 17)
            ])
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let newRecords = chartRecords(from: previousWeekStart, counts: [0, 0, 2, 0, 0, 0, 0])
        var mergedCounts = existingCounts
        for record in newRecords {
            mergedCounts[record.date] = record.date == thirdDay ? [john: 2] : [:]
        }

        // When
        await store.send(.view(.loadMoreBefore(fixedChartDay(-1))))

        // Then: 기록은 새 주 뒤에 기존 기록이 이어지고, 장별 횟수는 기존 두 날짜를 그대로 둔 채 7일이 더해진다
        await store.receive(\.setFetchedDailyData) {
            $0.dailyRecordChart.records = newRecords + existingRecords
            $0.chapterCountsByDay = mergedCounts
            $0.drawingWeeklySummary.chapterCountsByDay = mergedCounts
            $0.earliestFetchedDate = previousWeekStart
        }
        #expect(store.state.chapterCountsByDay[fixedChartDay(-1)] == [genesis: 2])
        #expect(store.state.chapterCountsByDay[fixedChartDay(0)] == [john: 1])
        await store.receive(\.dailyRecordChart)
        await store.receive(\.endAppending)
    }

    @Test("진행 중 표시는 조회 · 병합 · 위치 보정 내내 켜져 있다가 endAppending 에서 꺼진다")
    @MainActor
    func loadMoreBeforeKeepsAppendingFlagUntilEndAppending() async {
        // Given: 하한이 직전 주 중간이라 일부 날만 붙는 경로
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: fixedChartDay(0))!.start
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let lowerBound = calendar.date(byAdding: .day, value: 5, to: previousWeekStart)!
        let store = TestStore(initialState: loadMoreState(earliest: fixedChartDay(0), lowerBound: lowerBound)) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RangeRecordingActivityRepository()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When: 보내는 순간 켜진다
        await store.send(.view(.loadMoreBefore(fixedChartDay(0)))) {
            $0.isAppendingPastData = true
        }

        // Then: 병합 · 위치 보정 동안에는 켜져 있다
        await store.receive(\.setFetchedDailyData)
        #expect(store.state.isAppendingPastData)
        await store.receive(\.dailyRecordChart)
        #expect(store.state.isAppendingPastData)
        // Then: 마지막 endAppending 에서 꺼진다
        await store.receive(\.endAppending) {
            $0.isAppendingPastData = false
        }
    }

    /// State 의 날짜 필드를 고정 날짜로 채운다(State 기본값은 실제 오늘을 쓴다).
    private func loadMoreState(earliest: Date, lowerBound: Date = fixedChartDay(-30)) -> DrawingChartFeature.State {
        var state = DrawingChartFeature.State()
        state.lowerBoundDate = lowerBound
        state.earliestFetchedDate = earliest
        state.dailyRecordChart.lowerBoundDate = lowerBound
        state.dailyRecordChart.scrollPosition = fixedChartDay(0)
        state.drawingWeeklySummary.scrollPosition = fixedChartDay(0)
        return state
    }
}

/// 받은 조회 기간을 기록하고, 주어진 활동 중 그 기간 안의 것만 돌려주는 저장소.
private actor RangeRecordingActivityRepository: DrawingActivityRepository {
    private let activities: [DrawingActivity]
    private(set) var receivedRanges: [DateInterval] = []

    init(activities: [DrawingActivity] = []) {
        self.activities = activities
    }

    func activities(in range: DateInterval) async throws -> [DrawingActivity] {
        receivedRanges.append(range)
        return activities.filter { activity in
            guard let date = activity.updateDate else { return false }
            return date >= range.start && date < range.end
        }
    }

    func recentActivities(limit: Int) async throws -> [DrawingActivity] {
        []
    }
}

/// 장 · 절 · 시각으로 필사 활동 하나를 만든다.
private func loadMoreActivity(_ date: Date, _ chapter: BibleChapter, verse: Int) -> DrawingActivity {
    DrawingActivity(updateDate: date, titleName: chapter.title.rawValue, titleChapter: chapter.chapter, verse: verse)
}
