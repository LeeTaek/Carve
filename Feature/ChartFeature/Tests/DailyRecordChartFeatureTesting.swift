//
//  DailyRecordChartFeatureTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/22/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Foundation
import Testing

struct DailyRecordChartFeatureTesting {
    // MARK: - 페이지 · Y축 계산

    @Test("차트가 나타나면 폭을 기록하고 보이는 주를 가운데로 세 페이지를 만든다")
    @MainActor
    func onAppearBuildsThreePagesAroundVisibleWeek() async {
        // Given: 최신 주(오늘-6 ~ 오늘)를 보고 있고 지난 14일 기록이 있다
        let records = chartRecords(from: fixedChartDay(-13), counts: [1, 0, 2, 5, 0, 0, 3, 1, 1, 0, 2, 0, 4, 1])
        let state = DailyRecordChartFeature.State(
            records: records,
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: fixedChartDay(-6)
        )
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.onAppear(width: 600))) {
            $0.pageWidth = 600
        }
        await store.receive(\.rebuild, true)

        // Then: 다음 페이지는 오늘을 넘지 않도록 최신 주에 고정된다
        #expect(store.state.pages.map(\.start) == [fixedChartDay(-13), fixedChartDay(-6), fixedChartDay(-6)])
        #expect(store.state.pages[1].end == fixedChartDay(0))
        #expect(store.state.pages[1].xDomain == fixedChartDay(-6)...fixedChartDay(1))
        #expect(store.state.pages[0].entries.map(\.count) == [1, 0, 2, 5, 0, 0, 3])
        #expect(store.state.pages[1].entries.map(\.count) == [1, 1, 0, 2, 0, 4, 1])
        // 세 페이지 최댓값 5 + 여유 ceil(5 × 0.4) = 2
        #expect(store.state.yScale == 0...7)
        #expect(store.state.visibleStartDate == fixedChartDay(-6))
        #expect(store.state.visibleEndDate == fixedChartDay(0))
    }

    @Test("페이지를 만들 때 기록은 날짜 순으로 정렬하고 주 밖 기록은 뺀다")
    @MainActor
    func rebuildSortsEntriesAndDropsOutsideWeek() async {
        // Given: 순서가 섞인 기록과 보이는 세 페이지 밖(오늘-30) 기록
        let records = [
            DailyRecord(date: fixedChartDay(-2), count: 2),
            DailyRecord(date: fixedChartDay(-5), count: 1),
            DailyRecord(date: fixedChartDay(-30), count: 9),
            DailyRecord(date: fixedChartDay(-4), count: 3)
        ]
        let store = TestStore(
            initialState: DailyRecordChartFeature.State(
                records: records,
                lowerBoundDate: fixedChartDay(-40),
                scrollPosition: fixedChartDay(-6)
            )
        ) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.rebuild(force: true))

        // Then
        #expect(store.state.pages[1].entries.map(\.date) == [fixedChartDay(-5), fixedChartDay(-4), fixedChartDay(-2)])
        #expect(store.state.pages.allSatisfy { !$0.entries.contains { $0.count == 9 } })
        #expect(store.state.yScale == 0...5)
    }

    @Test("기록이 모두 0이면 Y축 범위를 바꾸지 않는다")
    @MainActor
    func rebuildKeepsYScaleWhenAllCountsAreZero() async {
        // Given
        var state = DailyRecordChartFeature.State(
            records: chartRecords(from: fixedChartDay(-6), counts: Array(repeating: 0, count: 7)),
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: fixedChartDay(-6)
        )
        state.yScale = 0...12
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.rebuild(force: true))

        // Then
        #expect(store.state.pages.count == 3)
        #expect(store.state.yScale == 0...12)
    }

    @Test(
        "Y축 상한은 최댓값에 40% 여유(최소 1)를 더한다",
        arguments: [
            (counts: [1], upper: 2.0),
            (counts: [0, 2, 1], upper: 3.0),
            (counts: [5], upper: 7.0),
            (counts: [3, 10], upper: 14.0),
            (counts: [11], upper: 16.0)
        ]
    )
    func targetYScaleAddsHeadroom(counts: [Int], upper: Double) {
        // Given
        let start = fixedChartDay(-6)
        let page = ChartPage(
            start: start,
            end: fixedChartDay(0),
            entries: chartRecords(from: start, counts: counts),
            xDomain: start...fixedChartDay(1)
        )

        // When
        let scale = DailyRecordChartFeature().targetYScale(for: [page])

        // Then
        #expect(scale == 0...upper)
    }

    @Test("기록이 없거나 모두 0이면 목표 Y축이 없다")
    func targetYScaleIsNilWithoutPositiveCounts() {
        let start = fixedChartDay(-6)
        let emptyPage = ChartPage(start: start, end: fixedChartDay(0), entries: [], xDomain: start...fixedChartDay(1))
        let zeroPage = ChartPage(
            start: start,
            end: fixedChartDay(0),
            entries: chartRecords(from: start, counts: [0, 0]),
            xDomain: start...fixedChartDay(1)
        )

        #expect(DailyRecordChartFeature().targetYScale(for: []) == nil)
        #expect(DailyRecordChartFeature().targetYScale(for: [emptyPage, zeroPage]) == nil)
    }

    // MARK: - 주 이동 버튼

    @Test("하한에 닿은 주에서는 이전 7일 버튼이 아무 일도 하지 않는다")
    @MainActor
    func previousWeekTappedIsIgnoredAtLowerBound() async {
        // Given: 오늘-27 에서 7일 앞(오늘-34)은 하한(오늘-30)보다 이르다
        let store = TestStore(
            initialState: DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-27))
        ) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        #expect(!store.state.canMoveToPreviousWeek)

        // When / Then: 상태 변화도 효과도 없다
        await store.send(.view(.previousWeekTapped))
    }

    @Test("오늘을 포함한 주에서는 다음 7일 버튼이 아무 일도 하지 않는다")
    @MainActor
    func nextWeekTappedIsIgnoredOnLatestWeek() async {
        // 과도기: 버튼 가드인 canMoveToNextWeek 가 실제 오늘을 읽으므로 실제 날짜를 쓴다
        let store = TestStore(
            initialState: DailyRecordChartFeature.State(lowerBoundDate: chartDay(-30), scrollPosition: chartDay(-6))
        ) {
            DailyRecordChartFeature()
        } withDependencies: { liveTimeDependencies(&$0) }
        #expect(!store.state.canMoveToNextWeek)

        await store.send(.view(.nextWeekTapped))
    }

    @Test("이전 7일 버튼은 페이지 전환을 시작하고 끝나면 7일 앞 주로 옮긴다")
    @MainActor
    func previousWeekTappedPagesToEarlierWeek() async {
        // Given: 끝에서 canMoveToNextWeek(실제 오늘 기준)를 보므로 날짜는 과도기 헬퍼를 쓴다
        let clock = TestClock()
        var state = DailyRecordChartFeature.State(lowerBoundDate: chartDay(-30), scrollPosition: chartDay(-6))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: {
            liveTimeDependencies(&$0)
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        #expect(store.state.canMoveToPreviousWeek)

        // When: 버튼 → commitMove(.prev)
        await store.send(.view(.previousWeekTapped))
        await store.receive(\.commitMove, .prev)

        // Then: 전환 중에는 한 페이지 폭만큼 밀려 있다
        #expect(store.state.isPaging)
        #expect(store.state.dragX == 600)

        // When: 전환 애니메이션이 끝난다
        await clock.advance(by: .milliseconds(240))
        await store.receive(\.finishMove, .prev)

        // Then
        #expect(store.state.scrollPosition == chartDay(-13))
        #expect(!store.state.isPaging)
        #expect(!store.state.isScrolling)
        #expect(store.state.dragX == 0)
        #expect(store.state.pages.map(\.start) == [chartDay(-20), chartDay(-13), chartDay(-6)])
        #expect(store.state.canMoveToNextWeek)
    }

    @Test("다음 7일 버튼은 끝나면 7일 뒤 주로 옮긴다")
    @MainActor
    func nextWeekTappedPagesToLaterWeek() async {
        let clock = TestClock()
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.view(.nextWeekTapped))
        await store.receive(\.commitMove, .next)
        #expect(store.state.dragX == -600)

        await clock.advance(by: .milliseconds(240))
        await store.receive(\.finishMove, .next)

        #expect(store.state.scrollPosition == fixedChartDay(-6))
        #expect(!store.state.isPaging)
        #expect(store.state.dragX == 0)
    }
}

// MARK: - 이동 완료 · 드래그 · 접근성

extension DailyRecordChartFeatureTesting {
    @Test("이전 주의 최댓값이 더 작으면 Y축을 잠시 유지했다가 목표 범위로 줄인다")
    @MainActor
    func finishMoveShrinksYScaleAfterDelay() async {
        // Given: 지금 페이지들의 Y축은 0...20, 이동 뒤 세 페이지 최댓값은 2
        let clock = TestClock()
        var state = DailyRecordChartFeature.State(
            records: chartRecords(from: fixedChartDay(-20), counts: [1, 2, 1, 0, 0, 1, 2]),
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: fixedChartDay(-6)
        )
        state.pageWidth = 600
        state.yScale = 0...20
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.finishMove(.prev))

        // Then: 페이지는 바로 바뀌고 Y축은 아직 넓은 채로 남는다
        #expect(store.state.scrollPosition == fixedChartDay(-13))
        #expect(store.state.yScale == 0...20)

        // Then: 짧은 지연 뒤 목표 범위(2 + 1)로 줄어든다
        await clock.advance(by: .milliseconds(40))
        await store.receive(\.applyYScale, 0...3)
        #expect(store.state.yScale == 0...3)
    }

    @Test("페이지 전환은 240ms 가 지나야 끝나고 그 전의 드래그는 무시한다")
    @MainActor
    func commitMoveFinishesOnlyAfter240Milliseconds() async {
        // Given
        let clock = TestClock()
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.continuousClock = clock
        }

        // When: 이전 주로 전환을 시작한다
        await store.send(.commitMove(.prev)) {
            $0.isPaging = true
            $0.dragX = 600
        }

        // Then: 239ms 까지는 끝나지 않아 드래그가 무시된다(받은 액션이 있으면 망라 모드 send 가 실패한다)
        await clock.advance(by: .milliseconds(239))
        await store.send(.view(.dragChanged(translationX: 50)))

        // When: 마지막 1ms 가 지난다
        await clock.advance(by: .milliseconds(1))

        // Then: 7일 앞 주로 옮기고 전환 상태를 푼다
        await store.receive(\.finishMove, .prev) {
            $0.isPaging = false
            $0.dragX = 0
            $0.scrollPosition = fixedChartDay(-20)
            $0.pages = [fixedChartDay(-27), fixedChartDay(-20), fixedChartDay(-13)].map { start in
                ChartPage(
                    start: start,
                    end: Calendar.current.date(byAdding: .day, value: 6, to: start)!,
                    entries: [],
                    xDomain: start...Calendar.current.date(byAdding: .day, value: 7, to: start)!
                )
            }
        }
    }

    // MARK: - 드래그

    @Test("페이지 전환 중에는 드래그를 무시한다")
    @MainActor
    func dragIsIgnoredWhilePaging() async {
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        state.isPaging = true
        state.selectedDate = fixedChartDay(-10)
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        // 상태 변화도 효과도 없어야 한다
        await store.send(.view(.dragChanged(translationX: 120)))
        await store.send(.view(.dragEnded(translationX: 400)))
    }

    @Test("이동할 수 있는 방향의 드래그는 손가락을 따라가고 선택을 해제한다")
    @MainActor
    func dragChangedFollowsFingerWhenMovable() async {
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        state.selectedDate = fixedChartDay(-10)
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        await store.send(.view(.dragChanged(translationX: 100))) {
            $0.isScrolling = true
            $0.selectedDate = nil
            $0.dragX = 100
        }
    }

    @Test("한 페이지 폭을 넘는 드래그는 넘친 만큼 감쇠한다")
    @MainActor
    func dragChangedDampsBeyondPageWidth() async {
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When: 폭 600 을 100 넘게 끈다
        await store.send(.view(.dragChanged(translationX: -700)))

        // Then: 넘친 100 은 최대 90(폭의 15%) 을 향해 감쇠한다 → 90 × 100 / 190
        let expected = -(600 + 90 * 100 / 190.0)
        #expect(abs(store.state.dragX - expected) < 0.001)
    }

    @Test("이동할 수 없는 방향의 드래그는 32pt 안에서 고무줄처럼 늘어난다")
    @MainActor
    func dragChangedRubberBandsTowardBlockedDirection() async {
        // Given: 최신 주라 다음(왼쪽 드래그)으로 갈 수 없다
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-6))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }
        store.exhaustivity = .off(showSkippedAssertions: false)

        // When
        await store.send(.view(.dragChanged(translationX: -1_000)))

        // Then: 32 × 1000 / 1032
        #expect(abs(store.state.dragX - (-32 * 1_000 / 1_032.0)) < 0.001)
        #expect(store.state.isScrolling)
    }

    @Test("폭을 재기 전에는 막힌 방향 드래그가 움직이지 않는다")
    @MainActor
    func rubberBandIsZeroWithoutPageWidth() async {
        let store = TestStore(
            initialState: DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-6))
        ) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        await store.send(.view(.dragChanged(translationX: -200))) {
            $0.isScrolling = true
            $0.dragX = 0
        }
    }

    @Test("문턱보다 짧은 드래그는 제자리로 돌아온다")
    @MainActor
    func shortDragEndedStaysOnSameWeek() async {
        // Given: 폭 600 의 문턱은 max(60, 90) = 90
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        state.dragX = 80
        state.isScrolling = true
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        // When
        await store.send(.view(.dragEnded(translationX: 80)))

        // Then: .stay 는 전환 없이 드래그만 되돌린다
        await store.receive(\.commitMove, .stay) {
            $0.dragX = 0
            $0.isScrolling = false
        }
    }

    @Test("문턱을 넘은 오른쪽 드래그는 이전 주로 넘긴다")
    @MainActor
    func longDragEndedMovesToPreviousWeek() async {
        let clock = TestClock()
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-13))
        state.pageWidth = 600
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: {
            fixedTimeDependencies(&$0)
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.view(.dragEnded(translationX: 200)))
        await store.receive(\.commitMove, .prev)
        await clock.advance(by: .milliseconds(240))
        await store.receive(\.finishMove, .prev)

        #expect(store.state.scrollPosition == fixedChartDay(-20))
    }

    @Test("문턱을 넘어도 갈 수 없는 방향이면 제자리로 돌아온다")
    @MainActor
    func longDragEndedStaysWhenDirectionBlocked() async {
        // Given: 최신 주에서 왼쪽(다음 주)으로 크게 끈다
        var state = DailyRecordChartFeature.State(lowerBoundDate: fixedChartDay(-30), scrollPosition: fixedChartDay(-6))
        state.pageWidth = 600
        state.dragX = -30
        state.isScrolling = true
        let store = TestStore(initialState: state) {
            DailyRecordChartFeature()
        } withDependencies: { fixedTimeDependencies(&$0) }

        await store.send(.view(.dragEnded(translationX: -300)))
        await store.receive(\.commitMove, .stay) {
            $0.dragX = 0
            $0.isScrolling = false
        }
    }

    // MARK: - 표시 범위 · 접근성

    @Test("페이지가 없으면 보이는 범위는 스크롤 위치부터 7일이다")
    func visibleRangeFallsBackToScrollPosition() {
        let state = DailyRecordChartFeature.State(
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: fixedChartDay(-13).addingTimeInterval(3_600 * 5)
        )

        #expect(state.visibleStartDate == fixedChartDay(-13))
        #expect(state.visibleEndDate == fixedChartDay(-7))
    }

    @Test("일주일 내내 기록이 있으면 기록 없는 날이 없다고 말한다")
    func accessibilitySummaryWithoutZeroDays() {
        let start = fixedChartDay(-6)
        let state = DailyRecordChartFeature.State(
            records: chartRecords(from: start, counts: [1, 1, 1, 1, 1, 1, 8]),
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: start
        )

        #expect(state.accessibilitySummary.contains("모두 14절, 하루 평균 2.0절"))
        #expect(state.accessibilitySummary.contains("가장 많은 날은 \(fixedChartDay(0).chartMonthDayText) 8절"))
        #expect(state.accessibilitySummary.contains("기록 없는 날은 없어요"))
    }

    @Test("기록이 없는 주는 가장 많은 날이 없고 7일 모두 없는 날로 센다")
    func accessibilitySummaryForEmptyWeek() {
        let start = fixedChartDay(-6)
        let state = DailyRecordChartFeature.State(
            records: chartRecords(from: start, counts: Array(repeating: 0, count: 7)),
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: start
        )

        #expect(state.accessibilitySummary.contains("모두 0절, 하루 평균 0.0절"))
        #expect(state.accessibilitySummary.contains("가장 많은 날은 없어요"))
        #expect(state.accessibilitySummary.contains("없는 날은 7일"))
    }

    @Test("최댓값이 같은 날이 여럿이면 가장 이른 날을 말하고 하루 빈 날은 하루로 말한다")
    func accessibilitySummaryPicksEarliestMaximumDay() {
        let start = fixedChartDay(-6)
        let state = DailyRecordChartFeature.State(
            records: chartRecords(from: start, counts: [1, 4, 2, 0, 4, 1, 1]),
            lowerBoundDate: fixedChartDay(-30),
            scrollPosition: start
        )

        #expect(state.accessibilitySummary.contains("가장 많은 날은 \(fixedChartDay(-5).chartMonthDayText) 4절"))
        #expect(state.accessibilitySummary.contains("없는 날은 하루"))
    }
}
