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
    /// 접근성 문장에서 읽는 월 · 일(기기 로케일) — ko 「9월 4일」 · en 「September 4」.
    var chartMonthDayText: String { chartMonthDayText(locale: nil) }

    /// 접근성 문장의 월 · 일을 한 로케일로 적는다. 월 이름은 줄이지 않는다 — VoiceOver 가 약어를 그대로 읽지 않게 한다.
    /// - Parameter locale: 날짜를 적을 로케일. nil 이면 기기 로케일이다.
    func chartMonthDayText(locale: Locale?) -> String {
        formatted(
            Date.FormatStyle()
                .locale(locale ?? .autoupdatingCurrent)
                .month(.wide)
                .day(.defaultDigits)
        )
    }

    /// 화면(주 머리 · X축)에 적는 짧은 월 · 일(기기 로케일) — ko 「9월 4일」 · en 「Sep 4」.
    var chartShortMonthDayText: String {
        formatted(
            Date.FormatStyle()
                .locale(.autoupdatingCurrent)
                .month(.abbreviated)
                .day(.defaultDigits)
        )
    }

    /// X축 날짜 아래의 요일(기기 로케일) — ko 「금」 · en 「Fri」.
    var chartWeekdayText: String {
        formatted(
            Date.FormatStyle()
                .locale(.autoupdatingCurrent)
                .weekday(.abbreviated)
        )
    }
}
