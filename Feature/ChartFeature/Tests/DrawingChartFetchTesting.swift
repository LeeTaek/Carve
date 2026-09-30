//
//  DrawingChartFetchTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/28/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 차트 첫 조회(`.view(.fetchData)`)의 조회 범위와 값이 빠진 활동의 대체 규칙을 본다.
/// 정상 경로(30일 집계 · 최근 항목 최신순 · 빈 저장소)는 `DrawingChartFeatureTesting` 에 있다.
struct DrawingChartFetchTesting {
    @Test("첫 조회는 고정 오늘을 포함한 30일 구간과 최근 5개를 저장소에 묻는다")
    @MainActor
    func fetchDataRequestsThirtyDayRangeAndFiveRecent() async {
        // Given
        let repository = RecordingDrawingActivityRepository()
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = repository
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)
        await store.receive(\.setRecentItems)

        // Then: [오늘-29일 자정, 내일 자정) 한 번, limit 5 한 번
        #expect(repository.ranges.value == [DateInterval(start: fixedChartDay(-29), end: fixedChartDay(1))])
        #expect(repository.limits.value == [5])
    }

    @Test("고친 시각이 없는 활동은 오늘 필사로 센다")
    @MainActor
    func fetchDataCountsMissingUpdateDateAsToday() async {
        // Given
        let john = BibleChapter(title: .john, chapter: 3)
        let activity = DrawingActivity(updateDate: nil, titleName: john.title.rawValue, titleChapter: john.chapter, verse: 16)
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RecordingDrawingActivityRepository(activities: [activity])
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then
        let records = store.state.dailyRecordChart.records
        #expect(records.last == DailyRecord(date: fixedChartDay(0), count: 1))
        #expect(records.dropLast().map(\.count).allSatisfy { $0 == 0 })
        #expect(store.state.chapterCountsByDay[fixedChartDay(0)] == [john: 1])
    }

    @Test("권 이름을 알 수 없거나 장이 없는 활동은 날짜별 개수에만 들어가고 장별 횟수에서는 빠진다")
    @MainActor
    func fetchDataSkipsUnknownChapterInChapterCounts() async {
        // Given: 어제 모르는 권 하나, 장이 없는 절 하나, 요한복음 3장 하나
        let john = BibleChapter(title: .john, chapter: 3)
        let yesterday = fixedChartDay(-1).addingTimeInterval(3_600)
        let activities = [
            DrawingActivity(updateDate: yesterday, titleName: "Unknown.txt", titleChapter: 2, verse: 1),
            DrawingActivity(updateDate: yesterday, titleName: john.title.rawValue, titleChapter: nil, verse: 1),
            DrawingActivity(updateDate: yesterday, titleName: john.title.rawValue, titleChapter: john.chapter, verse: 16)
        ]
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RecordingDrawingActivityRepository(activities: activities)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then
        let records = store.state.dailyRecordChart.records
        #expect(records.first { $0.date == fixedChartDay(-1) }?.count == 3)
        #expect(store.state.chapterCountsByDay[fixedChartDay(-1)] == [john: 1])
    }

    @Test("최근 절에서 빠진 권 · 장 · 절은 창세기 1장 1절로, 빠진 시각은 먼 미래로 채우고 시각이 없는 항목은 맨 뒤에 둔다")
    @MainActor
    func fetchDataFillsMissingRecentFieldsAndSortsNilLast() async {
        // Given: 저장소가 순서 없이 돌려준다
        let john = BibleChapter(title: .john, chapter: 3)
        let romans = BibleChapter(title: .romans, chapter: 8)
        let older = Date(timeIntervalSince1970: 1_000)
        let middle = Date(timeIntervalSince1970: 2_000)
        let newer = Date(timeIntervalSince1970: 3_000)
        let recent = [
            DrawingActivity(updateDate: nil, titleName: nil, titleChapter: nil, verse: nil),
            DrawingActivity(updateDate: middle, titleName: john.title.rawValue, titleChapter: john.chapter, verse: 16),
            DrawingActivity(updateDate: older, titleName: "Unknown.txt", titleChapter: 5, verse: 7),
            DrawingActivity(updateDate: newer, titleName: romans.title.rawValue, titleChapter: romans.chapter, verse: 28)
        ]
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RecordingDrawingActivityRepository(recent: recent)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 최신순, 모르는 권은 창세기로, 전부 빠진 항목은 창세기 1장 1절 · 먼 미래로 맨 뒤
        await store.receive(\.setRecentItems) {
            $0.drawingWeeklySummary.recentVerses = [
                recentVerse(romans, verse: 28, at: newer),
                recentVerse(john, verse: 16, at: middle),
                recentVerse(BibleChapter(title: .genesis, chapter: 5), verse: 7, at: older),
                recentVerse(BibleChapter(title: .genesis, chapter: 1), verse: 1, at: .distantFuture)
            ]
            // 장 목록은 권 · 장을 알 수 있는 항목만 담는다
            $0.drawingWeeklySummary.recentChapters = [romans, john]
        }
    }
}

/// 받은 조회 인자를 기록하고 주어진 활동을 그대로 돌려주는 저장소.
private final class RecordingDrawingActivityRepository: DrawingActivityRepository {
    let activities: [DrawingActivity]
    let recent: [DrawingActivity]
    let ranges = LockIsolated<[DateInterval]>([])
    let limits = LockIsolated<[Int]>([])

    init(activities: [DrawingActivity] = [], recent: [DrawingActivity] = []) {
        self.activities = activities
        self.recent = recent
    }

    func activities(in range: DateInterval) async throws -> [DrawingActivity] {
        ranges.withValue { $0.append(range) }
        return activities
    }

    func recentActivities(limit: Int) async throws -> [DrawingActivity] {
        limits.withValue { $0.append(limit) }
        return recent
    }
}

/// 장 · 절 · 시각으로 최근 항목 하나를 만든다.
private func recentVerse(_ chapter: BibleChapter, verse: Int, at date: Date) -> RecentVerseItem {
    RecentVerseItem(verse: BibleVerse(title: chapter, verse: verse, sentence: ""), updatedAt: date)
}
