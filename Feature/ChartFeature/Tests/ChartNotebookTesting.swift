//
//  ChartNotebookTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 10/16/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 2.2 회차별 필사책 — 차트 · 주간 요약은 모든 필사책을 합산하고, 최근 절 · 장 · 가장 많이 쓴 장은 그 필사책으로 연다(결정 10).
///
/// 날짜별 · 주간 수는 행 수, 장별 수 · 가장 많이 쓴 장은 `BibleChapter`(번역본 포함) 키로 필사책을 합산한다.
/// 활동의 필사책은 `DrawingActivity.page`(`StoredBookKey.decodeRow`)로 읽는다. 시각은 `ChartTestSupport` 의 고정 시각이다.
@MainActor
struct ChartNotebookTesting {
    /// 기본이 아닌 필사책 A — `nb_0f3a1c2d00004000800000000000000a~` 접두 행이다.
    private static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-00000000000A")!)
    private static let genesis = BibleChapter(title: .genesis, chapter: 1)
    private static let john = BibleChapter(title: .john, chapter: 3)
    private static let johnKJV = BibleChapter(title: .john, chapter: 3, translation: .KJV)
    private static let romans = BibleChapter(title: .romans, chapter: 8)

    /// 주간 요약이 그 필사책 · 장의 그 절을 열라고 알렸는가. 위임 값이 튜플이라 `Equatable` 로 견주지 못해 꺼내어 본다.
    private static func isOpenVerse(_ page: NotebookChapter, verse: Int) -> (DrawingChartFeature.Action) -> Bool {
        { action in
            guard case let .drawingWeeklySummary(.openVerse(receivedPage, receivedVerse)) = action else { return false }
            return receivedPage == page && receivedVerse == verse
        }
    }

    // MARK: - 모든 필사책 합산

    @Test("기본 필사책과 다른 필사책의 활동은 날짜별 수 · 주간 합계에 함께 센다")
    func dailyCountsSumAllNotebooks() async {
        // Given: 오늘 요한복음 3장 16절을 기본 · A 필사책에서 한 번씩, 어제 A 필사책에서 로마서 8장 28절
        let today = fixedChartDay(0)
        let yesterday = fixedChartDay(-1)
        let store = makeStore(activities: [
            notebookActivity(today.addingTimeInterval(7_200), .default, Self.john, verse: 16),
            notebookActivity(today.addingTimeInterval(3_600), Self.notebookA, Self.john, verse: 16),
            notebookActivity(yesterday.addingTimeInterval(3_600), Self.notebookA, Self.romans, verse: 28)
        ])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 필사책을 가리지 않고 행 수로 센다
        let records = store.state.dailyRecordChart.records
        #expect(records.last == DailyRecord(date: today, count: 2))
        #expect(records.first { $0.date == yesterday }?.count == 1)
        #expect(store.state.drawingWeeklySummary.weekTotalCount == 3)
        await store.receive(\.setRecentItems)
    }

    @Test("같은 장을 두 필사책에서 쓰면 장별 수에서 한 장으로 합산하고, 가장 많이 쓴 장도 합산한 수로 고른다")
    func chapterCountsMergeNotebooks() async {
        // Given: 오늘 요한복음 3장을 A 에서 두 절 · 기본에서 한 절, KJV 로 A 에서 한 절, 창세기 1장을 기본에서 두 절
        //   필사책마다 따로 세면 A 의 요한복음(2)과 기본의 창세기(2)가 같아 성경 순서로 창세기가 앞서지만, 합산하면 요한복음(3)이 가장 많다.
        let today = fixedChartDay(0)
        let store = makeStore(activities: [
            notebookActivity(today.addingTimeInterval(6_000), Self.notebookA, Self.johnKJV, verse: 16),
            notebookActivity(today.addingTimeInterval(5_000), Self.notebookA, Self.john, verse: 18),
            notebookActivity(today.addingTimeInterval(4_000), Self.notebookA, Self.john, verse: 17),
            notebookActivity(today.addingTimeInterval(3_000), .default, Self.john, verse: 16),
            notebookActivity(today.addingTimeInterval(2_000), .default, Self.genesis, verse: 2),
            notebookActivity(today.addingTimeInterval(1_000), .default, Self.genesis, verse: 1)
        ])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 장별 수는 필사책을 합산한 장(번역본 포함)마다 하나 — 번역본은 필사책을 합산해도 따로다
        #expect(store.state.chapterCountsByDay[today] == [Self.john: 3, Self.johnKJV: 1, Self.genesis: 2])
        #expect(store.state.drawingWeeklySummary.chapterCountsByDay[today] == [Self.john: 3, Self.johnKJV: 1, Self.genesis: 2])
        #expect(store.state.drawingWeeklySummary.topChapter?.chapter == Self.john)
        #expect(store.state.drawingWeeklySummary.topChapter?.count == 3)
        await store.receive(\.setRecentItems)
    }

    // MARK: - 최근 기록은 그 필사책으로

    @Test("최근 절이 다른 필사책의 행이면 그 필사책의 page 를 담고, 누르면 그 필사책 · 장의 절을 연다")
    func recentVerseInOtherNotebookOpensThatPage() async throws {
        // Given: 가장 최근에 A 필사책에서 요한복음 3장 16절(KJV)을, 그 전에 기본 필사책에서 로마서 8장 28절을 고쳤다
        let today = fixedChartDay(0)
        let pageA = NotebookChapter(notebook: Self.notebookA, chapter: Self.johnKJV)
        let store = makeStore(recent: [
            notebookActivity(today.addingTimeInterval(3_600), Self.notebookA, Self.johnKJV, verse: 16),
            notebookActivity(today.addingTimeInterval(1_800), .default, Self.romans, verse: 28)
        ])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)
        await store.receive(\.setRecentItems)

        // Then: 최근 절은 그 행의 필사책 · 번역본 장을 든다
        let recentVerses = store.state.drawingWeeklySummary.recentVerses
        #expect(recentVerses.map(\.page) == [pageA, NotebookChapter(notebook: .default, chapter: Self.romans)])
        let item = try #require(recentVerses.first)

        // When: 그 절을 누르면
        await store.send(.drawingWeeklySummary(.view(.recentVerseTapped(item))))

        // Then: 지금 필사책이 아니라 A 필사책 · KJV 장의 16절을 열도록 알린다
        await store.receive(Self.isOpenVerse(pageA, verse: 16))
    }

    @Test("같은 절을 두 필사책에서 고쳤으면 최근 절은 두 줄이고 항목 id 가 다르다")
    func sameVerseInTwoNotebooksHasDistinctRecentIDs() async {
        // Given: 같은 시각에 요한복음 3장 16절을 기본 · A 필사책에서 고쳤다
        let updatedAt = fixedChartDay(0).addingTimeInterval(3_600)
        let store = makeStore(recent: [
            notebookActivity(updatedAt, .default, Self.john, verse: 16),
            notebookActivity(updatedAt, Self.notebookA, Self.john, verse: 16)
        ])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)
        await store.receive(\.setRecentItems)

        // Then: 절 · 시각이 같아도 필사책이 달라 목록(`ForEach`)에서 겹치지 않는다
        let recentVerses = store.state.drawingWeeklySummary.recentVerses
        #expect(recentVerses.count == 2)
        #expect(Set(recentVerses.map(\.page)) == [
            NotebookChapter(notebook: .default, chapter: Self.john),
            NotebookChapter(notebook: Self.notebookA, chapter: Self.john)
        ])
        #expect(Set(recentVerses.map(\.id)).count == 2)
    }

    @Test("같은 장을 두 필사책에서 쓰면 최근 장은 한 줄이고, 누르면 그 장을 마지막으로 쓴 필사책으로 연다")
    func recentChapterMergesNotebooksAndOpensLatest() async {
        // Given: 요한복음 3장을 A 에서(가장 최근) · 기본에서 썼고, 그 사이에 로마서 8장을 기본에서 썼다
        let today = fixedChartDay(0)
        let johnInA = NotebookChapter(notebook: Self.notebookA, chapter: Self.john)
        let romansInDefault = NotebookChapter(notebook: .default, chapter: Self.romans)
        let store = makeStore(recent: [
            notebookActivity(today.addingTimeInterval(3_000), Self.notebookA, Self.john, verse: 17),
            notebookActivity(today.addingTimeInterval(2_000), .default, Self.romans, verse: 28),
            notebookActivity(today.addingTimeInterval(1_000), .default, Self.john, verse: 16)
        ])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 장은 필사책을 합산해 한 번씩, 그 장을 마지막으로 쓴 필사책의 장으로 담는다
        await store.receive(\.setRecentItems) {
            $0.drawingWeeklySummary.recentChapters = [johnInA, romansInDefault]
        }

        // When: 요한복음 3장을 누르면
        await store.send(.drawingWeeklySummary(.view(.recentChapterTapped(johnInA))))

        // Then: A 필사책의 요한복음 3장을 열도록 알린다
        await store.receive(\.drawingWeeklySummary.openChapter, johnInA)
    }

    // MARK: - 가장 많이 쓴 장

    @Test("가장 많이 쓴 장은 이번 주에 그 장을 마지막으로 쓴 필사책으로 연다 — 같은 날이면 늦게 쓴 필사책이다")
    func topChapterOpensNotebookThatLastWroteIt() async {
        // Given: 사흘 전 기본에서 요한복음 3장 세 절, 어제 기본(9시)과 A(10시)에서 한 절씩, 오늘 기본에서 로마서 8장 두 절
        //   어제 행은 이른 것이 먼저 오게 둔다 — 도착 순서가 아니라 고친 시각으로 고른다.
        let threeDaysAgo = fixedChartDay(-3)
        let yesterday = fixedChartDay(-1)
        let today = fixedChartDay(0)
        let store = makeStore(activities: [
            notebookActivity(today.addingTimeInterval(2_000), .default, Self.romans, verse: 2),
            notebookActivity(today.addingTimeInterval(1_000), .default, Self.romans, verse: 1),
            notebookActivity(yesterday.addingTimeInterval(9 * 3_600), .default, Self.john, verse: 20),
            notebookActivity(yesterday.addingTimeInterval(10 * 3_600), Self.notebookA, Self.john, verse: 19),
            notebookActivity(threeDaysAgo.addingTimeInterval(3_000), .default, Self.john, verse: 18),
            notebookActivity(threeDaysAgo.addingTimeInterval(2_000), .default, Self.john, verse: 17),
            notebookActivity(threeDaysAgo.addingTimeInterval(1_000), .default, Self.john, verse: 16)
        ])
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)
        await store.receive(\.setRecentItems)
        #expect(store.state.chapterNotebooksByDay[yesterday] == [Self.john: Self.notebookA])
        #expect(store.state.chapterNotebooksByDay[threeDaysAgo] == [Self.john: .default])
        #expect(store.state.drawingWeeklySummary.topChapter?.chapter == Self.john)
        #expect(store.state.drawingWeeklySummary.topChapter?.count == 5)

        // When
        await store.send(.drawingWeeklySummary(.view(.topChapterTapped)))

        // Then: 수는 기본 필사책이 많지만 이어서 쓸 곳은 마지막으로 쓴 A 필사책이다
        await store.receive(\.drawingWeeklySummary.openChapter, NotebookChapter(notebook: Self.notebookA, chapter: Self.john))
    }

    @Test("가장 많이 쓴 장을 여는 필사책은 보이는 주 안에서 그 장을 마지막으로 쓴 날의 것이고, 주 밖의 날은 보지 않는다")
    func topChapterPageUsesLatestDayInVisibleWeek() {
        // Given: 보이는 주(기준일-6 ~ 기준일)의 첫날은 기본, 나흘째는 A, 주 밖(기준일+1)은 기본에서 요한복음 3장을 썼다
        let start = fixedChartDay(-6)
        let fourthDay = fixedChartDay(-3)
        let outside = fixedChartDay(1)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [start: [Self.john: 2], fourthDay: [Self.john: 1], outside: [Self.john: 9]]
        state.chapterNotebooksByDay = [start: [Self.john: .default], fourthDay: [Self.john: Self.notebookA], outside: [Self.john: .default]]

        // Then: 수는 주 안만 합산하고, 여는 곳은 주 안에서 가장 늦은 날의 A 필사책이다
        #expect(state.topChapter?.count == 3)
        #expect(state.topChapterPage == NotebookChapter(notebook: Self.notebookA, chapter: Self.john))
    }

    @Test("가장 많이 쓴 장을 쓴 필사책을 모르면 눌러도 기본 필사책으로 바꿔 열지 않는다")
    func topChapterWithoutNotebookDoesNotOpen() async {
        // Given: 장별 수만 있고 장별 필사책이 없다(손으로 만든 상태 — 조회는 둘을 같은 행에서 함께 만든다)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = fixedChartDay(-6)
        state.chapterCountsByDay = [fixedChartDay(-6): [Self.john: 2]]
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        #expect(store.state.topChapter?.chapter == Self.john)
        #expect(store.state.topChapterPage == nil)

        // When / Then: 아무 알림도 나오지 않는다
        await store.send(.view(.topChapterTapped))
    }

    // MARK: - 과거 주 추가 조회 · 풀지 못하는 행

    @Test("과거 주를 더 불러오면 장별 필사책도 장별 수처럼 붙인 날의 값을 더하고, 이미 있던 날은 그대로 둔다")
    func loadMoreMergesChapterNotebooks() async {
        // Given: 오늘 기본 필사책에서 요한복음 3장을 쓴 기록이 이미 있고, 직전 주 둘째 날에 A 필사책에서 같은 장을 썼다
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: fixedChartDay(0))!.start
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: previousWeekStart)!
        var state = notebookChartState()
        state.dailyRecordChart.records = [DailyRecord(date: fixedChartDay(0), count: 1)]
        state.chapterCountsByDay = [fixedChartDay(0): [Self.john: 1]]
        state.chapterNotebooksByDay = [fixedChartDay(0): [Self.john: .default]]
        let store = makeStore(
            initialState: state,
            activities: [notebookActivity(secondDay.addingTimeInterval(3_600), Self.notebookA, Self.john, verse: 16)]
        )

        // When
        await store.send(.view(.loadMoreBefore(fixedChartDay(0))))
        await store.receive(\.setFetchedDailyData)

        // Then: 붙인 날은 그날의 필사책, 기록 없는 날은 빈 값, 이미 있던 오늘은 그대로 — 주간 요약도 같은 값을 본다
        let notebooks = store.state.chapterNotebooksByDay
        #expect(notebooks[secondDay] == [Self.john: Self.notebookA])
        #expect(notebooks[previousWeekStart] == [:])
        #expect(notebooks[fixedChartDay(0)] == [Self.john: .default])
        #expect(store.state.chapterCountsByDay[secondDay] == [Self.john: 1])
        #expect(store.state.drawingWeeklySummary.chapterNotebooksByDay == notebooks)
        await store.receive(\.dailyRecordChart)
        await store.receive(\.endAppending)
    }

    @Test("필사책 접두가 깨진 행은 날짜별 수에만 들고, 장별 수 · 최근 항목에서는 기본 필사책으로 바꾸지 않고 건너뛴다")
    func malformedNotebookPrefixCountsOnlyInDailyRecords() async {
        // Given: 오늘 접두가 깨진 요한복음 3장 행 둘(기본 필사책 토큰 · 대문자 토큰)과 기본 필사책 행 하나
        let today = fixedChartDay(0)
        let johnTitleName = StoredBookKey.titleName(for: NotebookChapter(notebook: .default, chapter: Self.john))
        let broken = ["nb_default~", "nb_0F3A1C2D00004000800000000000000A~"].enumerated().map { offset, prefix in
            DrawingActivity(
                updateDate: today.addingTimeInterval(TimeInterval(2_000 + offset * 1_000)),
                titleName: prefix + johnTitleName,
                titleChapter: Self.john.chapter,
                verse: 16
            )
        }
        let valid = notebookActivity(today.addingTimeInterval(1_000), .default, Self.john, verse: 16)
        let validItem = RecentVerseItem(
            verse: BibleVerse(title: Self.john, verse: 16, sentence: ""),
            updatedAt: today.addingTimeInterval(1_000),
            notebook: .default
        )
        let validPage = NotebookChapter(notebook: .default, chapter: Self.john)
        let store = makeStore(activities: broken + [valid], recent: broken + [valid])

        // When
        await store.send(.view(.fetchData))
        await store.receive(\.setFetchedDailyData)

        // Then: 날짜별 수는 셋, 장별 수 · 장별 필사책은 풀리는 행 하나뿐이다
        #expect(store.state.dailyRecordChart.records.last == DailyRecord(date: today, count: 3))
        #expect(store.state.chapterCountsByDay[today] == [Self.john: 1])
        #expect(store.state.chapterNotebooksByDay[today] == [Self.john: .default])

        // Then: 최근 절 · 장도 풀리는 행만 담는다
        await store.receive(\.setRecentItems) {
            $0.drawingWeeklySummary.recentVerses = [validItem]
            $0.drawingWeeklySummary.recentChapters = [validPage]
        }
    }

    // MARK: - 도우미

    /// 주어진 활동을 돌려주는 저장소로 차트 스토어를 만든다 — 날짜 필드는 고정 시각 기준이고, 비망라로 본다.
    private func makeStore(
        initialState: DrawingChartFeature.State = notebookChartState(),
        activities: [DrawingActivity] = [],
        recent: [DrawingActivity] = []
    ) -> TestStoreOf<DrawingChartFeature> {
        let store = TestStore(initialState: initialState) {
            DrawingChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.drawingActivityRepository = NotebookActivityRepository(activities: activities, recent: recent)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }
}

/// State 의 오늘 기준 날짜 필드를 고정 시각 기준으로 채운다(State 기본값은 실제 오늘을 쓴다).
private func notebookChartState() -> DrawingChartFeature.State {
    var state = DrawingChartFeature.State()
    state.lowerBoundDate = fixedChartDay(-30)
    state.earliestFetchedDate = fixedChartDay(0)
    state.dailyRecordChart.lowerBoundDate = fixedChartDay(-30)
    state.dailyRecordChart.scrollPosition = fixedChartDay(0)
    state.drawingWeeklySummary.scrollPosition = fixedChartDay(0)
    return state
}

/// 필사책 · 장 · 절 · 시각으로 필사 활동 하나를 만든다 — 행 이름은 저장 행처럼 `StoredBookKey` 로 짓는다(기본 필사책은 접두 없음).
private func notebookActivity(_ date: Date, _ notebook: NotebookID, _ chapter: BibleChapter, verse: Int) -> DrawingActivity {
    DrawingActivity(updateDate: date, page: NotebookChapter(notebook: notebook, chapter: chapter), verse: verse)
}

/// 주어진 활동을 돌려주는 저장소 — 기간 조회는 그 기간 안의 것을 주어진 순서대로, 최근 조회는 앞에서 `limit` 개를 돌려준다.
private struct NotebookActivityRepository: DrawingActivityRepository {
    let activities: [DrawingActivity]
    let recent: [DrawingActivity]

    func activities(in range: DateInterval) async throws -> [DrawingActivity] {
        activities.filter { activity in
            guard let date = activity.updateDate else { return false }
            return date >= range.start && date < range.end
        }
    }

    func recentActivities(limit: Int) async throws -> [DrawingActivity] {
        Array(recent.prefix(max(limit, 0)))
    }
}
