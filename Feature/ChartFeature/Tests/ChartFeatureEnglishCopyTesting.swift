//
//  ChartFeatureEnglishCopyTesting.swift
//  ChartFeatureTest
//
//  Created by Claude on 10/12/26.
//

@testable import ChartFeature
import Foundation
import Testing

/// 차트 문구(접근성 요약 · 절 수 단위 · 주 머리 · X축 라벨)가 영어로도 옮겨졌는지 본다(영어 현지화 결정 5 · 6 · 7).
/// 언어는 로케일로 명시한다 — 시험은 ko-KR 로 돌므로 로케일 없는 경로는 한국어다.
struct ChartFeatureEnglishCopyTesting {
    private static let english = Locale(identifier: "en")
    private static let korean = Locale(identifier: "ko")

    @Test("접근성 요약은 영어에서 날짜 · 절 수 · 기록 없는 날을 영어 문장으로 말한다")
    func accessibilitySummaryInEnglish() {
        let state = Self.state(startingAt: Self.september4, counts: [0, 2, 3, 0, 1, 3, 3])

        #expect(state.accessibilitySummary(locale: Self.english) == """
        Chart. September 4 to September 10. Verses written per day. 12 verses in total, 1.7 verses a day on average. \
        Most on September 6 with 3 verses, 2 days with no record.
        """)
    }

    @Test("한국어 접근성 요약은 카탈로그를 거쳐도 예전 문장과 같다")
    func accessibilitySummaryInKoreanIsUnchanged() {
        let state = Self.state(startingAt: Self.september4, counts: [0, 2, 3, 0, 1, 3, 3])

        #expect(state.accessibilitySummary(locale: Self.korean) == """
        차트. 9월 4일부터 9월 10일까지. 하루에 필사한 절 수. 모두 12절, 하루 평균 1.7절. 가장 많은 날은 9월 6일 3절, 없는 날은 이틀.
        """)
    }

    @Test("영어 접근성 요약 — 한 절은 단수, 한국어 수사(하루)는 숫자, 빈 주와 빈 날 없는 주도 영어로 말한다")
    func accessibilitySummaryEnglishEdgeCases() {
        let single = Self.state(startingAt: Self.september4, counts: [1, 0, 0, 0, 0, 0, 0])
        #expect(single.accessibilitySummary(locale: Self.english).contains("1 verse in total, 0.1 verses a day on average."))
        #expect(single.accessibilitySummary(locale: Self.english).contains("Most on September 4 with 1 verse, 6 days with no record."))

        let oneEmptyDay = Self.state(startingAt: Self.september4, counts: [1, 4, 2, 0, 4, 1, 1])
        #expect(oneEmptyDay.accessibilitySummary(locale: Self.english).hasSuffix("Most on September 5 with 4 verses, 1 day with no record."))

        let empty = Self.state(startingAt: Self.september4, counts: Array(repeating: 0, count: 7))
        #expect(empty.accessibilitySummary(locale: Self.english).hasSuffix(
            "0 verses in total, 0.0 verses a day on average. No busiest day, 7 days with no record."
        ))

        let full = Self.state(startingAt: Self.september4, counts: [1, 1, 1, 1, 1, 1, 8])
        #expect(full.accessibilitySummary(locale: Self.english).hasSuffix("Most on September 10 with 8 verses, every day has a record."))
    }

    @Test("절 수 · 주 머리는 영어 복수형을 따르고 X축 라벨은 영어에서 요일이 앞에 온다")
    func unitsAndLabelsInEnglish() {
        #expect(ChartCatalog.string("\(1)절", locale: Self.english) == "1 verse")
        #expect(ChartCatalog.string("\(3)절", locale: Self.english) == "3 verses")
        #expect(ChartCatalog.string("\(3)절", locale: Self.korean) == "3절")
        #expect(ChartCatalog.string("\("1.7")절", locale: Self.english) == "1.7 verses")
        #expect(ChartCatalog.string("\(1)주 전", locale: Self.english) == "1 week ago")
        #expect(ChartCatalog.string("\(3)주 전", locale: Self.english) == "3 weeks ago")
        #expect(ChartCatalog.string("\(3)주 전", locale: Self.korean) == "3주 전")
        #expect(ChartCatalog.string("\("Sep 4") \("Fri")", locale: Self.english) == "Fri Sep 4")
        #expect(ChartCatalog.string("\("9월 4일") \("금")", locale: Self.korean) == "9월 4일 금")
    }

    @Test("접근성 날짜는 로케일 서식이다 — 한국어는 예전 고정 ko_KR 표기와 같다")
    func monthDayFollowsLocale() {
        #expect(Self.september4.chartMonthDayText(locale: Self.english) == "September 4")
        #expect(Self.september4.chartMonthDayText(locale: Locale(identifier: "ko_KR")) == "9월 4일")
    }

    // MARK: - 시험 자료

    /// 2026-09-04 자정(기기 시간대).
    private static let september4: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
    }()

    /// `start` 부터 7일을 보이는 차트 상태 — 날마다 `counts` 절.
    private static func state(startingAt start: Date, counts: [Int]) -> DailyRecordChartFeature.State {
        DailyRecordChartFeature.State(
            records: chartRecords(from: start, counts: counts),
            lowerBoundDate: start,
            scrollPosition: start
        )
    }
}
