//
//  DailyRecord.swift
//  ChartFeature
//
//  Created by 이택성 on 12/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct DailyRecord: Equatable, Identifiable {
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
    /// 차트의 기간 및 접근성 문장에서 사용하는 한국어 월·일 표기다.
    var chartMonthDayText: String {
        formatted(
            Date.FormatStyle()
                .locale(Locale(identifier: "ko_KR"))
                .month(.wide)
                .day(.defaultDigits)
        )
    }
}
