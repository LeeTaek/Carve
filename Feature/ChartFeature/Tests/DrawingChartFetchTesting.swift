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

    @Test("최근 절은 권 · 번역본을 모르거나 장이 없는 활동을 건너뛰고, 빠진 절은 1절로 빠진 시각은 먼 미래로 채워 맨 뒤에 둔다")
    @MainActor
    func fetchDataSkipsUnknownRecentChaptersAndSortsNilLast() async {
        // Given: 저장소가 순서 없이 돌려준다 — 모르는 권 · 모르는 번역본 접두 · 장 없는 행이 섞여 있다
        let john = BibleChapter(title: .john, chapter: 3)
        let romans = BibleChapter(title: .romans, chapter: 8)
        let psalms = BibleChapter(title: .psalms, chapter: 23)
        let oldest = Date(timeIntervalSince1970: 500)
        let older = Date(timeIntervalSince1970: 1_000)
        let middle = Date(timeIntervalSince1970: 2_000)
        let newer = Date(timeIntervalSince1970: 3_000)
        let recent = [
            DrawingActivity(updateDate: nil, titleName: nil, titleChapter: nil, verse: nil),
            DrawingActivity(updateDate: middle, titleName: john.title.rawValue, titleChapter: john.chapter, verse: 16),
            DrawingActivity(updateDate: older, titleName: "Unknown.txt", titleChapter: 5, verse: 7),
            DrawingActivity(updateDate: oldest, titleName: "ESV-\(BibleTitle.genesis.rawValue)", titleChapter: 1, verse: 1),
            DrawingActivity(updateDate: older, titleName: john.title.rawValue, titleChapter: nil, verse: 3),
            DrawingActivity(updateDate: nil, titleName: psalms.title.rawValue, titleChapter: psalms.chapter, verse: nil),
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

        // Then: 최신순, 창세기 등 다른 자리로 바꿔 담지 않는다. 시각이 없는 시편은 1절 · 먼 미래로 맨 뒤
        await store.receive(\.setRecentItems) {
            $0.drawingWeeklySummary.recentVerses = [
                recentVerse(romans, verse: 28, at: newer),
                recentVerse(john, verse: 16, at: middle),
                recentVerse(psalms, verse: 1, at: .distantFuture)
            ]
            // 장 목록도 권 · 장 · 번역본을 알 수 있는 항목만 담는다
            $0.drawingWeeklySummary.recentChapters = [romans, john, psalms]
        }
    }

    @Test("같은 권 · 장도 KJV 와 개역개정은 장별 횟수 · 최근 장에서 따로 세고, 최근 절은 그 번역본 장을 든다")
    @MainActor
    func fetchDataSeparatesTranslationsOfSameChapter() async {
        // Given: 오늘 요한복음 3장을 개역개정으로 두 절, KJV 로 한 절(KJV 행의 권 이름은 번역본 접두가 붙는다)
        let john = BibleChapter(title: .john, chapter: 3)
        let johnKJV = BibleChapter(title: .john, chapter: 3, translation: .KJV)
        let today = fixedChartDay(0)
        let activities = [
            DrawingActivity(updateDate: today.addingTimeInterval(3_600), chapter: johnKJV, verse: 16),
            DrawingActivity(updateDate: today.addingTimeInterval(2_400), chapter: john, verse: 17),
            DrawingActivity(updateDate: today.addingTimeInterval(1_200), chapter: john, verse: 16)
        ]
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = RecordingDrawingActivityRepository(activities: activities, recent: activities)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 날짜별 수는 셋 다, 장별 횟수는 번역본마다 따로
        #expect(store.state.dailyRecordChart.records.last == DailyRecord(date: today, count: 3))
        #expect(store.state.chapterCountsByDay[today] == [john: 2, johnKJV: 1])
        await store.receive(\.setRecentItems) {
            $0.drawingWeeklySummary.recentVerses = [
                recentVerse(johnKJV, verse: 16, at: today.addingTimeInterval(3_600)),
                recentVerse(john, verse: 17, at: today.addingTimeInterval(2_400)),
                recentVerse(john, verse: 16, at: today.addingTimeInterval(1_200))
            ]
            $0.drawingWeeklySummary.recentChapters = [johnKJV, john]
        }
        // 주간 요약의 가장 많이 쓴 장도 번역본마다 따로 센 값이다
        #expect(store.state.drawingWeeklySummary.chapterCountsByDay[today] == [john: 2, johnKJV: 1])
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
