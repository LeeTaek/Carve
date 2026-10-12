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
    @Test("최근 필사 항목은 성경 위치를 한글 표시 문자열로 만들고, 개역개정은 약칭을 생략한다(사용자 결정 17)")
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

    @Test("KJV 최근 필사 항목도 권 · 장절은 앱 언어(한국어)로 적고 뒤에 KJV 를 붙인다")
    func recentVerseItemMessageShowsKJVAbbreviation() {
        let item = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .john, chapter: 3, translation: .KJV), verse: 16, sentence: ""),
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        #expect(item.message == "요한복음 3장 16절 · KJV")
    }

    @Test("차트 목록의 장 참조(최근 장 · 가장 많이 쓴 장)는 KJV · BSB 만 약칭을 붙이고 개역개정은 생략한다 — 영어 기기도 같다(사용자 결정 17)")
    func chartChapterReferenceOmitsNKRVAbbreviation() {
        let english = Locale(identifier: "en")
        let nkrv = BibleChapter(title: .psalms, chapter: 23)
        let kjv = BibleChapter(title: .psalms, chapter: 23, translation: .KJV)
        let bsb = BibleChapter(title: .john, chapter: 3, translation: .BSB)

        #expect(BibleReference(chartChapter: nkrv).text == "시편 23장")
        #expect(BibleReference(chartChapter: kjv).text == "시편 23장 · KJV")
        #expect(BibleReference(chartChapter: bsb).text == "요한복음 3장 · BSB")
        #expect(BibleReference(chartChapter: nkrv).text(locale: english) == "Psalm 23")
        #expect(BibleReference(chartChapter: kjv).text(locale: english) == "Psalm 23 · KJV")
        #expect(BibleReference(chartChapter: bsb, verses: .verse(16)).text(locale: english) == "John 3:16 · BSB")
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

    @Test("같은 절 · 같은 시각이라도 번역본이 다르면 최근 필사 항목 식별자가 다르다")
    func recentVerseItemIDSeparatesTranslations() {
        let updatedAt = Date(timeIntervalSince1970: 2_400)
        let korean = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .psalms, chapter: 23), verse: 1, sentence: ""), updatedAt: updatedAt
        )
        let english = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .psalms, chapter: 23, translation: .KJV), verse: 1, sentence: ""), updatedAt: updatedAt
        )

        #expect(english.id == "KJV-1-19Psalms.txt|23|1|2400.0")
        #expect(korean.id != english.id)
    }

    @Test("일별 기록의 식별자는 날짜와 동일하다")
    func dailyRecordIDMatchesDate() {
        let date = Date(timeIntervalSince1970: 3_600)
        let record = DailyRecord(date: date, count: 7)

        #expect(record.id == date)
    }
}
