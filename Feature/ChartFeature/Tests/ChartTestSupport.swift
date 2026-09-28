//
//  ChartTestSupport.swift
//  ChartFeatureTest
//
//  Created by Claude on 9/22/26.
//

@testable import ChartFeature
import ComposableArchitecture
import Foundation

// TestStore 는 State: Equatable 을 요구한다. 제품 State 는 Equatable 이 아니므로
// 테스트 타깃 안에서만 저장 프로퍼티 전체를 비교하는 준수를 붙인다.
// 제품 쪽에 Equatable 이 생기면 이 확장은 지운다.

extension DrawingWeeklySummaryFeature.State: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.adSlotState == rhs.adSlotState
            && lhs.scrollPosition == rhs.scrollPosition
            && lhs.dailyRecords == rhs.dailyRecords
            && lhs.chapterCountsByDay == rhs.chapterCountsByDay
            && lhs.recentVerses == rhs.recentVerses
            && lhs.recentChapters == rhs.recentChapters
    }
}

extension DrawingChartFeature.State: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dailyRecordChart == rhs.dailyRecordChart
            && lhs.drawingWeeklySummary == rhs.drawingWeeklySummary
            && lhs.earliestFetchedDate == rhs.earliestFetchedDate
            && lhs.lowerBoundDate == rhs.lowerBoundDate
            && lhs.isAppendingPastData == rhs.isAppendingPastData
            && lhs.selectedRecord == rhs.selectedRecord
            && lhs.chapterCountsByDay == rhs.chapterCountsByDay
    }
}

/// 차트 테스트가 기준으로 삼는 고정 시각(2026-01-14 12:00 UTC).
enum ChartTestTime {
    static let now = Date(timeIntervalSince1970: 1_768_392_000)
}

/// 고정 시각의 자정에서 `offset` 일 떨어진 날의 자정을 돌려준다.
func fixedChartDay(_ offset: Int) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: ChartTestTime.now)
    return calendar.date(byAdding: .day, value: offset, to: today)!
}

/// 날짜를 고정 시각으로, 시계를 즉시 끝나는 시계로 둔다.
func fixedTimeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.date = .constant(ChartTestTime.now)
    dependencies.continuousClock = ImmediateClock()
}

/// 실제 현재 시각과 실제 시계를 쓴다. State 기본값 · State 계산 프로퍼티처럼 제품 코드가 `Date()` 를 직접 읽는
/// 경로를 검증할 때만 쓴다. 새 테스트는 `fixedTimeDependencies` 를 쓴다.
func liveTimeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.date = .constant(Date())
    dependencies.continuousClock = ContinuousClock()
}

/// 실제 오늘 자정에서 `offset` 일 떨어진 날의 자정을 돌려준다. State 기본값 · State 계산 프로퍼티처럼
/// 제품 코드가 `Date()` 를 직접 읽는 경로를 검증할 때만 쓴다. 새 테스트는 `fixedChartDay` 를 쓴다.
func chartDay(_ offset: Int) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return calendar.date(byAdding: .day, value: offset, to: today)!
}

/// `start` 부터 하루씩 `counts` 를 기록으로 만든다.
func chartRecords(from start: Date, counts: [Int]) -> [DailyRecord] {
    counts.enumerated().map { offset, count in
        DailyRecord(date: Calendar.current.date(byAdding: .day, value: offset, to: start)!, count: count)
    }
}
