//
//  DrawingChartFeatureTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/22/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

struct DrawingChartFeatureTesting {
    @Test("초기 상태는 오늘 기준 30일 하한과 오늘 스크롤 위치를 하위 기능과 맞춘다")
    func initialStateAlignsChildrenWithToday() {
        let state = DrawingChartFeature.State()

        #expect(state.lowerBoundDate == chartDay(-30))
        #expect(state.earliestFetchedDate == chartDay(0))
        #expect(state.dailyRecordChart.lowerBoundDate == chartDay(-30))
        #expect(state.dailyRecordChart.scrollPosition == chartDay(0))
        #expect(state.drawingWeeklySummary.scrollPosition == chartDay(0))
        #expect(!state.isAppendingPastData)
        #expect(state.selectedRecord == nil)
    }

    @Test("빈 상태에서 필사로 돌아가기를 누르면 부모에게 알린다")
    @MainActor
    func backToWritingSendsDelegate() async {
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        await store.send(.view(.backToWriting))
        await store.receive(\.delegate)
    }

    @Test("불러온 일별 기록은 마지막 날을 선택하고 그 주를 보이도록 하위 기능에 나눠 준다")
    @MainActor
    func setFetchedDailyDataSelectsLatestDayAndSyncsChildren() async {
        // Given
        let records = chartRecords(from: chartDay(-29), counts: Array(repeating: 0, count: 29) + [3])
        let chapter = BibleChapter(title: .john, chapter: 3)
        let counts: [Date: [BibleChapter: Int]] = [chartDay(0): [chapter: 3]]
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then: 스크롤은 마지막 날 6일 전, 선택은 마지막 날
        await store.send(.setFetchedDailyData(dailyRecords: records, chapterCountsByDay: counts)) {
            $0.chapterCountsByDay = counts
            $0.earliestFetchedDate = chartDay(-29)
            $0.selectedRecord = records.last
            $0.dailyRecordChart.records = records
            $0.dailyRecordChart.scrollPosition = chartDay(-6)
            $0.dailyRecordChart.selectedDate = chartDay(0)
            $0.drawingWeeklySummary.dailyRecords = records
            $0.drawingWeeklySummary.scrollPosition = chartDay(-6)
            $0.drawingWeeklySummary.chapterCountsByDay = counts
        }
        #expect(store.state.drawingWeeklySummary.weekTotalCount == 3)
        #expect(store.state.drawingWeeklySummary.topChapter?.chapter == chapter)
    }

    @Test("빈 일별 기록이 오면 선택을 지우고 스크롤 위치와 가장 이른 날은 그대로 둔다")
    @MainActor
    func setFetchedEmptyDailyDataClearsSelection() async {
        // Given: 이전에 선택한 날이 있다
        var state = DrawingChartFeature.State()
        let previous = DailyRecord(date: chartDay(-1), count: 2)
        state.dailyRecordChart.records = [previous]
        state.dailyRecordChart.selectedDate = previous.date
        state.selectedRecord = previous
        state.drawingWeeklySummary.dailyRecords = [previous]
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then
        await store.send(.setFetchedDailyData(dailyRecords: [], chapterCountsByDay: [:])) {
            $0.dailyRecordChart.records = []
            $0.dailyRecordChart.selectedDate = nil
            $0.selectedRecord = nil
            $0.drawingWeeklySummary.dailyRecords = []
        }
    }

    @Test("최근 필사 항목은 주간 요약에 그대로 넘긴다")
    @MainActor
    func setRecentItemsForwardsToWeeklySummary() async {
        let chapter = BibleChapter(title: .genesis, chapter: 1)
        let verses = [
            RecentVerseItem(
                verse: BibleVerse(title: chapter, verse: 2, sentence: ""),
                updatedAt: Date(timeIntervalSince1970: 3_600)
            )
        ]
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        await store.send(.setRecentItems(recentVerses: verses, recentChapters: [chapter])) {
            $0.drawingWeeklySummary.recentVerses = verses
            $0.drawingWeeklySummary.recentChapters = [chapter]
        }
    }

    @Test("막대를 누르면 그 날을 선택하고 해당 기록을 보여 준다")
    @MainActor
    func tapSymbolSelectsMatchingRecord() async {
        // Given
        let records = chartRecords(from: chartDay(-6), counts: [1, 2, 3, 4, 5, 6, 7])
        var state = DrawingChartFeature.State()
        state.dailyRecordChart.records = records
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then
        await store.send(.view(.tapSymbol(chartDay(-4)))) {
            $0.dailyRecordChart.selectedDate = chartDay(-4)
            $0.selectedRecord = records[2]
        }
    }

    @Test("기록에 없는 날을 누르면 날짜만 선택하고 보여 줄 기록은 없다")
    @MainActor
    func tapSymbolOnMissingDayClearsRecord() async {
        var state = DrawingChartFeature.State()
        let existing = DailyRecord(date: chartDay(-1), count: 2)
        state.dailyRecordChart.records = [existing]
        state.dailyRecordChart.selectedDate = existing.date
        state.selectedRecord = existing
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        await store.send(.view(.tapSymbol(chartDay(-3)))) {
            $0.dailyRecordChart.selectedDate = chartDay(-3)
            $0.selectedRecord = nil
        }
    }

    @Test("차트 하위 기능에서 선택이 바뀌면 선택 기록을 따라 바꾼다")
    @MainActor
    func childSelectedDateChangeUpdatesSelectedRecord() async {
        // Given
        let records = chartRecords(from: chartDay(-6), counts: [1, 2, 3, 4, 5, 6, 7])
        var state = DrawingChartFeature.State()
        state.dailyRecordChart.records = records
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When: 하위 차트가 바인딩으로 날짜를 고른다
        await store.send(.dailyRecordChart(.binding(.set(\.selectedDate, chartDay(-1)))))

        // Then
        #expect(store.state.selectedRecord == records[5])

        // When: 드래그 등으로 선택이 풀린다
        await store.send(.dailyRecordChart(.binding(.set(\.selectedDate, nil))))

        // Then
        #expect(store.state.selectedRecord == nil)
    }

    @Test("차트 하위 기능의 스크롤 위치가 바뀌면 주간 요약도 같은 주를 본다")
    @MainActor
    func childScrollPositionChangeSyncsWeeklySummary() async {
        let store = TestStore(initialState: DrawingChartFeature.State()) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.dailyRecordChart(.binding(.set(\.scrollPosition, chartDay(-13)))))

        #expect(store.state.dailyRecordChart.scrollPosition == chartDay(-13))
        #expect(store.state.drawingWeeklySummary.scrollPosition == chartDay(-13))
    }

    @Test("추가 로드가 끝나면 추가 중 표시를 내린다")
    @MainActor
    func endAppendingClearsFlag() async {
        var state = DrawingChartFeature.State()
        state.isAppendingPastData = true
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        await store.send(.endAppending) {
            $0.isAppendingPastData = false
        }
    }

    @Test("이미 하한까지 불러왔으면 과거 추가 로드는 조회 없이 바로 끝난다")
    @MainActor
    func loadMoreBeforeAtLowerBoundEndsImmediately() async {
        // Given: 가장 이른 날이 하한과 같다
        var state = DrawingChartFeature.State()
        state.earliestFetchedDate = state.lowerBoundDate
        let store = TestStore(initialState: state) {
            DrawingChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }

        // When / Then: 잠깐 추가 중으로 바뀌었다가 endAppending 으로 내려온다
        await store.send(.view(.loadMoreBefore(state.lowerBoundDate))) {
            $0.isAppendingPastData = true
        }
        await store.receive(\.endAppending) {
            $0.isAppendingPastData = false
        }
    }
}
