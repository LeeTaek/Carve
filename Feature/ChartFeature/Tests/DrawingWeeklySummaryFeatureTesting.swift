//
//  DrawingWeeklySummaryFeatureTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/22/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

struct DrawingWeeklySummaryFeatureTesting {
    // MARK: - 리듀서

    @Test("최근 필사 절을 누르면 그 절을 열도록 알린다")
    @MainActor
    func recentVerseTappedOpensVerse() async {
        // Given
        let item = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .john, chapter: 3), verse: 16, sentence: ""),
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )
        let store = TestStore(initialState: DrawingWeeklySummaryFeature.State()) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then: 상태는 그대로이고 openVerse 만 나온다
        await store.send(.view(.recentVerseTapped(item)))
        await store.receive(\.openVerse, item.verse)
    }

    @Test("최근 필사 장을 누르면 그 장을 열도록 알린다")
    @MainActor
    func recentChapterTappedOpensChapter() async {
        let chapter = BibleChapter(title: .psalms, chapter: 23)
        let store = TestStore(initialState: DrawingWeeklySummaryFeature.State()) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        await store.send(.view(.recentChapterTapped(chapter)))
        await store.receive(\.openChapter, chapter)
    }

    @Test("이번 주 가장 많이 쓴 장을 누르면 그 장을 열도록 알린다")
    @MainActor
    func topChapterTappedOpensTopChapter() async {
        // Given
        let start = chartDay(-6)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [start: [genesis: 1, john: 4]]
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then
        await store.send(.view(.topChapterTapped))
        await store.receive(\.openChapter, john)
    }

    @Test("이번 주 기록이 없으면 가장 많이 쓴 장을 눌러도 아무 일도 없다")
    @MainActor
    func topChapterTappedWithoutRecordsDoesNothing() async {
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = chartDay(-6)
        // 보이는 주 밖(오늘-7)의 기록만 있다
        state.chapterCountsByDay = [chartDay(-7): [BibleChapter(title: .genesis, chapter: 1): 3]]
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { liveTimeDependencies(&$0) }
        #expect(store.state.topChapter == nil)

        await store.send(.view(.topChapterTapped))
    }

    // MARK: - 주간 지표

    @Test(
        "하루 평균(정수)은 주간 합계를 7로 나눠 반올림한다",
        arguments: [
            (counts: [10], average: 1),
            (counts: [11], average: 2),
            (counts: [3, 0, 0, 0, 0, 0, 0], average: 0),
            (counts: [4, 0, 0, 0, 0, 0, 0], average: 1),
            (counts: [7, 7, 7, 7, 7, 7, 7], average: 7)
        ]
    )
    func weekAverageCountRoundsToNearest(counts: [Int], average: Int) {
        let start = chartDay(-6)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.dailyRecords = chartRecords(from: start, counts: counts)

        #expect(state.weekAverageCount == average)
    }

    @Test("기록이 없으면 하루 평균 표시는 0.0 이다")
    func weekAverageTextIsZeroWithoutRecords() {
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = chartDay(-6)

        #expect(state.weekAverageText == "0.0")
        #expect(state.weekMaxCount == 0)
    }

    @Test("스크롤 위치에 시각이 섞여 있어도 그날 자정부터 7일을 이번 주로 본다")
    func weekRangeStartsAtStartOfScrollDay() {
        // Given: 스크롤 위치가 오늘-6 의 오후
        let start = chartDay(-6)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start.addingTimeInterval(3_600 * 15)
        state.dailyRecords = [
            DailyRecord(date: start, count: 3),
            DailyRecord(date: chartDay(0).addingTimeInterval(3_600 * 23), count: 4),
            DailyRecord(date: chartDay(1), count: 50)
        ]

        // Then: 오늘-6 자정 기록과 오늘 23시 기록은 포함, 내일은 제외
        #expect(state.weekTotalCount == 7)
        #expect(state.weekMaxCount == 4)
    }

    @Test("권별 횟수는 보이는 주의 날짜 키가 자정일 때만 합산한다")
    func topChapterReadsOnlyMidnightDayKeys() {
        // Given: 같은 날이지만 자정이 아닌 키로 들어온 횟수
        let start = chartDay(-6)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let exodus = BibleChapter(title: .exodus, chapter: 20)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [
            start: [genesis: 1],
            start.addingTimeInterval(3_600): [exodus: 9]
        ]

        // Then: 현재 동작은 자정 키만 읽으므로 출애굽기 9는 빠진다
        #expect(state.topChapter?.chapter == genesis)
        #expect(state.topChapter?.count == 1)
    }
}
