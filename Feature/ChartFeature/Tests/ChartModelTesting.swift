//
//  ChartModelTesting.swift
//  ChartFeatureTests
//
//  Created by Codex on 5/20/26.
//

@testable import ChartFeature
import Domain
import Foundation
import Testing

struct ChartModelTesting {
    @Test("최근 필사 항목은 성경 위치를 한글 표시 문자열로 만든다")
    func recentVerseItemMessageUsesLocalizedBiblePosition() {
        let item = RecentVerseItem(
            verse: BibleVerse(
                title: BibleChapter(title: .john, chapter: 3),
                verse: 16,
                sentence: "하나님이 세상을 이처럼 사랑하사"
            ),
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        #expect(item.message == "요한복음 3장 16절")
    }

    @Test("최근 필사 항목 식별자는 성경 위치와 수정 시각으로 결정된다")
    func recentVerseItemIDUsesBiblePositionAndUpdatedAt() {
        let item = RecentVerseItem(
            verse: BibleVerse(
                title: BibleChapter(title: .psalms, chapter: 23),
                verse: 1,
                sentence: "여호와는 나의 목자시니"
            ),
            updatedAt: Date(timeIntervalSince1970: 2_400),
            drawingID: "drawing-1"
        )

        #expect(item.id == "1-19Psalms.txt|23|1|2400.0")
    }

    @Test("일별 기록의 식별자는 날짜와 동일하다")
    func dailyRecordIDMatchesDate() {
        let date = Date(timeIntervalSince1970: 3_600)
        let record = DailyRecord(date: date, count: 7)

        #expect(record.id == date)
    }
}
