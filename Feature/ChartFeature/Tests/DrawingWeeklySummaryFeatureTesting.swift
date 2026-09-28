//
//  DrawingWeeklySummaryFeatureTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/22/26.
//

@testable import ChartFeature
import ClientInterfaces
import ComposableArchitecture
import Domain
import Foundation
import Testing
import UIComponents
import UIKit

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
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = fixedChartDay(0)
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        // When / Then: 상태는 그대로이고 openVerse 만 나온다
        await store.send(.view(.recentVerseTapped(item)))
        await store.receive(\.openVerse, item.verse)
    }

    @Test("최근 필사 장을 누르면 그 장을 열도록 알린다")
    @MainActor
    func recentChapterTappedOpensChapter() async {
        let chapter = BibleChapter(title: .psalms, chapter: 23)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = fixedChartDay(0)
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        await store.send(.view(.recentChapterTapped(chapter)))
        await store.receive(\.openChapter, chapter)
    }

    @Test("이번 주 가장 많이 쓴 장을 누르면 그 장을 열도록 알린다")
    @MainActor
    func topChapterTappedOpensTopChapter() async {
        // Given
        let start = fixedChartDay(-6)
        let genesis = BibleChapter(title: .genesis, chapter: 1)
        let john = BibleChapter(title: .john, chapter: 3)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.chapterCountsByDay = [start: [genesis: 1, john: 4]]
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        // When / Then
        await store.send(.view(.topChapterTapped))
        await store.receive(\.openChapter, john)
    }

    @Test("이번 주 기록이 없으면 가장 많이 쓴 장을 눌러도 아무 일도 없다")
    @MainActor
    func topChapterTappedWithoutRecordsDoesNothing() async {
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = fixedChartDay(-6)
        // 보이는 주 밖(기준일-7)의 기록만 있다
        state.chapterCountsByDay = [fixedChartDay(-7): [BibleChapter(title: .genesis, chapter: 1): 3]]
        let store = TestStore(initialState: state) {
            DrawingWeeklySummaryFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        #expect(store.state.topChapter == nil)

        await store.send(.view(.topChapterTapped))
    }

    // MARK: - 광고 자리

    @Test("화면에 들어오면 차트 광고를 받는 동안 자리를 비워 두고, 광고가 오면 그 뷰를 든다")
    @MainActor
    func onAppearLoadsChartAd() async throws {
        // Given: 광고 제거를 사지 않았다
        let defaults = try makeAppStorage()
        defer { defaults.store.removePersistentDomain(forName: defaults.suiteName) }
        let adView = UIView()
        let client = StubNativeAdClient(outcomes: [.success(adView)])
        let clock = TestClock()
        let store = makeAdStore(client: client, clock: clock, appStorage: defaults.store)

        // When
        await store.send(.view(.onAppear))

        // Then: 로드 중에는 자리를 차지하고, 도착하면 광고를 든다
        await store.receive(\.adSlot.startLoad) {
            $0.adSlotState.isLoading = true
        }
        #expect(store.state.adSlotState.occupiesSpace)
        await store.receive(\.adSlot.adLoaded) {
            $0.adSlotState.isLoading = false
            $0.adSlotState.token = NativeAdToken(tokenId: "ad-0")
            $0.adSlotState.adView = adView
        }
        #expect(store.state.adSlotState.hasAd)
        #expect(client.requestedPlacements == [.chartCard])

        // 만료 타이머까지 끝내 남은 효과가 없게 한다 — 차트는 가끔 보이는 자리라 만료되면 비운다.
        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adSlot.adExpired) {
            $0.adSlotState.token = nil
            $0.adSlotState.adView = nil
        }
    }

    @Test("화면에 들어와 광고를 받지 못하면 자리를 없앤다")
    @MainActor
    func onAppearRemovesSlotWhenAdFails() async throws {
        // Given
        let defaults = try makeAppStorage()
        defer { defaults.store.removePersistentDomain(forName: defaults.suiteName) }
        let client = StubNativeAdClient(outcomes: [.failure])
        let store = makeAdStore(client: client, clock: TestClock(), appStorage: defaults.store)

        // When
        await store.send(.view(.onAppear))

        // Then
        await store.receive(\.adSlot.startLoad) {
            $0.adSlotState.isLoading = true
        }
        await store.receive(\.adSlot.adFailed) {
            $0.adSlotState.isLoading = false
            $0.adSlotState.errorMessage = String(describing: NativeAdClientError.adLoaderFailed(code: 1, message: "no fill"))
        }
        #expect(!store.state.adSlotState.occupiesSpace)
    }

    @Test("광고 제거를 샀으면 화면에 들어와도 광고를 요청하지 않고 자리도 두지 않는다")
    @MainActor
    func onAppearSkipsAdWhenAdFree() async throws {
        // Given: 광고 제거를 샀다
        let defaults = try makeAppStorage()
        defer { defaults.store.removePersistentDomain(forName: defaults.suiteName) }
        withDependencies {
            $0.defaultAppStorage = defaults.store
        } operation: {
            Shared<Bool>(.isAdFree)
        }
        .withLock { $0 = true }
        let client = StubNativeAdClient(outcomes: [])
        let store = makeAdStore(client: client, clock: TestClock(), appStorage: defaults.store)
        #expect(!store.state.adSlotState.occupiesSpace)

        // When
        await store.send(.view(.onAppear))

        // Then: 슬롯은 startLoad 를 받지만 상태도 요청도 없다
        await store.receive(\.adSlot.startLoad)
        #expect(client.requestedPlacements.isEmpty)
        #expect(!store.state.adSlotState.occupiesSpace)
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
        let start = fixedChartDay(-6)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start
        state.dailyRecords = chartRecords(from: start, counts: counts)

        #expect(state.weekAverageCount == average)
    }

    @Test("기록이 없으면 하루 평균 표시는 0.0 이다")
    func weekAverageTextIsZeroWithoutRecords() {
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = fixedChartDay(-6)

        #expect(state.weekAverageText == "0.0")
        #expect(state.weekMaxCount == 0)
    }

    @Test("스크롤 위치에 시각이 섞여 있어도 그날 자정부터 7일을 이번 주로 본다")
    func weekRangeStartsAtStartOfScrollDay() {
        // Given: 스크롤 위치가 기준일-6 의 오후
        let start = fixedChartDay(-6)
        var state = DrawingWeeklySummaryFeature.State()
        state.scrollPosition = start.addingTimeInterval(3_600 * 15)
        state.dailyRecords = [
            DailyRecord(date: start, count: 3),
            DailyRecord(date: fixedChartDay(0).addingTimeInterval(3_600 * 23), count: 4),
            DailyRecord(date: fixedChartDay(1), count: 50)
        ]

        // Then: 기준일-6 자정 기록과 기준일 23시 기록은 포함, 기준일+1 은 제외
        #expect(state.weekTotalCount == 7)
        #expect(state.weekMaxCount == 4)
    }

    @Test("권별 횟수는 보이는 주의 날짜 키가 자정일 때만 합산한다")
    func topChapterReadsOnlyMidnightDayKeys() {
        // Given: 같은 날이지만 자정이 아닌 키로 들어온 횟수
        let start = fixedChartDay(-6)
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

    /// 광고 제거 여부는 테스트마다 따로 둔다 — 기본 저장소를 함께 쓰면 다른 테스트의 광고 자리까지 사라진다.
    private func makeAppStorage() throws -> (store: UserDefaults, suiteName: String) {
        let suiteName = "DrawingWeeklySummaryFeatureTesting.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    @MainActor
    private func makeAdStore(
        client: StubNativeAdClient,
        clock: TestClock<Duration>,
        appStorage: UserDefaults
    ) -> TestStoreOf<DrawingWeeklySummaryFeature> {
        withDependencies {
            $0.defaultAppStorage = appStorage
        } operation: {
            var state = DrawingWeeklySummaryFeature.State()
            state.scrollPosition = fixedChartDay(0)
            return TestStore(initialState: state) {
                DrawingWeeklySummaryFeature()
            } withDependencies: {
                fixedTimeDependencies(&$0)
                $0.nativeAdClient = client
                $0.continuousClock = clock
            }
        }
    }
}

/// 정해 둔 순서대로 광고를 돌려주는 대역. 토큰은 요청 순번으로 `ad-<순번>` 이다.
@MainActor
private final class StubNativeAdClient: NativeAdClient {
    enum Outcome {
        case success(UIView)
        case failure
    }

    private var outcomes: [Outcome]
    private var views: [String: UIView] = [:]
    private(set) var requestedPlacements: [NativeAdPlacement] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func load(placement: NativeAdPlacement, adUnitId: String) async throws(NativeAdClientError) -> NativeAdToken {
        let tokenId = "ad-\(requestedPlacements.count)"
        requestedPlacements.append(placement)
        switch outcomes.removeFirst() {
        case .success(let view):
            views[tokenId] = view
            return NativeAdToken(tokenId: tokenId)
        case .failure:
            throw .adLoaderFailed(code: 1, message: "no fill")
        }
    }

    func view(for token: NativeAdToken) -> UIView? {
        views[token.tokenId]
    }

    func invalidate(token: NativeAdToken) {}
}
