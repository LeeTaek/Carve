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
    /// 한국어 화면 — 시험 스킴의 언어 · 지역(ko-KR)과 같다.
    private static let korean = Locale(identifier: "ko_KR")

    @Test("최근 필사 항목은 성경 위치를 한글 표시 문자열로 만들고, 개역개정은 약칭을 생략한다(사용자 결정 17)")
    func recentVerseItemMessageUsesLocalizedBiblePosition() {
        let item = RecentVerseItem(
            verse: BibleVerse(
                title: BibleChapter(title: .john, chapter: 3),
                verse: 16,
                sentence: "하나님이 세상을 이처럼 사랑하사"
            ),
            updatedAt: Date(timeIntervalSince1970: 1_800),
            notebook: .default
        )

        #expect(item.message(locale: Self.korean) == "요한복음 3장 16절")
    }

    @Test("KJV 최근 필사 항목도 권 · 장절은 앱 언어(한국어)로 적고 뒤에 KJV 를 붙인다")
    func recentVerseItemMessageShowsKJVAbbreviation() {
        let item = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .john, chapter: 3, translation: .KJV), verse: 16, sentence: ""),
            updatedAt: Date(timeIntervalSince1970: 1_800),
            notebook: .default
        )

        #expect(item.message(locale: Self.korean) == "요한복음 3장 16절 · KJV")
    }

    @Test("차트 목록의 장 참조(최근 장 · 가장 많이 쓴 장)는 KJV · BSB 만 약칭을 붙이고 개역개정은 생략한다 — 영어 기기도 같다(사용자 결정 17)")
    func chartChapterReferenceOmitsNKRVAbbreviation() {
        let english = Locale(identifier: "en")
        let nkrv = BibleChapter(title: .psalms, chapter: 23)
        let kjv = BibleChapter(title: .psalms, chapter: 23, translation: .KJV)
        let bsb = BibleChapter(title: .john, chapter: 3, translation: .BSB)

        #expect(BibleReference(chartChapter: nkrv).text(locale: Self.korean) == "시편 23장")
        #expect(BibleReference(chartChapter: kjv).text(locale: Self.korean) == "시편 23장 · KJV")
        #expect(BibleReference(chartChapter: bsb).text(locale: Self.korean) == "요한복음 3장 · BSB")
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
            notebook: .default,
            drawingID: "drawing-1"
        )

        #expect(item.id == "1-19Psalms.txt|23|1|2400.0")
    }

    @Test("같은 절 · 같은 시각이라도 번역본이 다르면 최근 필사 항목 식별자가 다르다")
    func recentVerseItemIDSeparatesTranslations() {
        let updatedAt = Date(timeIntervalSince1970: 2_400)
        let korean = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .psalms, chapter: 23), verse: 1, sentence: ""), updatedAt: updatedAt, notebook: .default
        )
        let english = RecentVerseItem(
            verse: BibleVerse(title: BibleChapter(title: .psalms, chapter: 23, translation: .KJV), verse: 1, sentence: ""),
            updatedAt: updatedAt,
            notebook: .default
        )

        #expect(english.id == "KJV-1-19Psalms.txt|23|1|2400.0")
        #expect(korean.id != english.id)
    }

    @Test("같은 절 · 같은 시각이라도 필사책이 다르면 최근 필사 항목 식별자가 다르고, 기본 필사책 식별자는 2.1 과 같다")
    func recentVerseItemIDSeparatesNotebooks() throws {
        // Given: 시편 23장 1절을 같은 시각에 기본 필사책과 다른 필사책에서 고쳤다
        let updatedAt = Date(timeIntervalSince1970: 2_400)
        let psalm = BibleVerse(title: BibleChapter(title: .psalms, chapter: 23), verse: 1, sentence: "")
        let notebook = try #require(NotebookID(rawValue: "0f3a1c2d00004000800000000000000a"))
        let first = RecentVerseItem(verse: psalm, updatedAt: updatedAt, notebook: .default)
        let second = RecentVerseItem(verse: psalm, updatedAt: updatedAt, notebook: notebook)

        // Then: 다른 필사책 항목은 행 이름처럼 필사책 접두가 붙어 목록에서 겹치지 않는다
        #expect(first.id == "1-19Psalms.txt|23|1|2400.0")
        #expect(second.id == "nb_0f3a1c2d00004000800000000000000a~1-19Psalms.txt|23|1|2400.0")
        #expect(first.id != second.id)
        #expect(second.page == NotebookChapter(notebook: notebook, chapter: psalm.title))
    }

    @Test("일별 기록의 식별자는 날짜와 동일하다")
    func dailyRecordIDMatchesDate() {
        let date = Date(timeIntervalSince1970: 3_600)
        let record = DailyRecord(date: date, count: 7)

        #expect(record.id == date)
    }
}
