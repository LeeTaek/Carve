//
//  DailyRecord.swift
//  ChartFeature
//
//  Created by 이택성 on 12/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct DailyRecord: Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var count: Int

    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }

    /// 해당 날짜에 한 절 이상 필사했는지 나타낸다.
    var hasDrawing: Bool {
        // `count`는 컬렉션이 아니라 절 수라 `isEmpty`를 사용할 수 없다.
        // swiftlint:disable:next empty_count
        count > 0
    }
}

extension Date {
    // 표시 서식만 로케일을 따른다 — 날짜 · 요일 경계(달력 · 시간대)는 기기 것 그대로다(`Date.FormatStyle()` 기본값).

    /// 접근성 문장의 월 · 일을 한 로케일로 적는다 — ko 「9월 4일」 · en 「September 4」.
    /// 월 이름은 줄이지 않는다 — VoiceOver 가 약어를 그대로 읽지 않게 한다.
    /// - Parameter locale: 날짜를 적을 로케일. 뷰는 환경 locale 을 넘긴다.
    func chartMonthDayText(locale: Locale) -> String {
        formatted(
            Date.FormatStyle()
                .locale(locale)
                .month(.wide)
                .day(.defaultDigits)
        )
    }

    /// 화면(주 머리 · X축)에 적는 짧은 월 · 일 — ko 「9월 4일」 · en 「Sep 4」.
    /// - Parameter locale: 날짜를 적을 로케일. 뷰는 환경 locale 을 넘긴다.
    func chartShortMonthDayText(locale: Locale) -> String {
        formatted(
            Date.FormatStyle()
                .locale(locale)
                .month(.abbreviated)
                .day(.defaultDigits)
        )
    }

    /// X축 날짜 아래의 요일 — ko 「금」 · en 「Fri」.
    /// - Parameter locale: 요일을 적을 로케일. 뷰는 환경 locale 을 넘긴다.
    func chartWeekdayText(locale: Locale) -> String {
        formatted(
            Date.FormatStyle()
                .locale(locale)
                .weekday(.abbreviated)
        )
    }
}
