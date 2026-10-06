//
//  BibleReferenceTesting.swift
//  DomainTest
//
//  Created by Claude on 10/6/26.
//

@testable import Domain
import Foundation
import Testing

/// 권 이름(`BibleTitle.localizedName`)과 참조 문자열(`BibleReference`)의 표시 규칙을 본다(영어 현지화 결정 3 · 11).
/// 언어는 로케일로 명시한다 — 시험은 ko-KR 로 돈다.
struct BibleReferenceTesting {
    private static let english = Locale(identifier: "en")
    private static let korean = Locale(identifier: "ko")

    // MARK: - 권 이름

    @Test("한국어 권 이름은 66권 모두 koreanTitle() 과 같다")
    func koreanNamesMatchKoreanTitle() {
        for title in BibleTitle.allCases {
            #expect(title.localizedName(locale: Self.korean) == title.koreanTitle())
        }
    }

    @Test("영어 권 이름은 66권 모두 검색용 영문 이름과 같다")
    func englishNamesMatchEnglishName() {
        #expect(Set(BibleTitle.allCases.map(\.englishName)).count == BibleTitle.allCases.count)
        for title in BibleTitle.allCases {
            #expect(title.localizedName(locale: Self.english) == title.englishName)
        }
    }

    @Test("영어 권 이름은 표준 이름이다 — 번호 있는 권 · 아가 · 시편 목록 이름")
    func englishNamesUseStandardNames() {
        #expect(BibleTitle.genesis.localizedName(locale: Self.english) == "Genesis")
        #expect(BibleTitle.samuel1.localizedName(locale: Self.english) == "1 Samuel")
        #expect(BibleTitle.songOfSongs.localizedName(locale: Self.english) == "Song of Solomon")
        #expect(BibleTitle.psalms.localizedName(locale: Self.english) == "Psalms")
        #expect(BibleTitle.john3.localizedName(locale: Self.english) == "3 John")
        #expect(BibleTitle.revelation.localizedName(locale: Self.english) == "Revelation")
    }

    @Test("로케일을 주지 않으면 앱 언어(시험은 ko-KR)를 따른다")
    func defaultLocaleFollowsAppLanguage() {
        #expect(BibleTitle.genesis.localizedName == "창세기")
        #expect(BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1), verse: 1).text == "창세기 1장 1절")
        #expect(Translation.NKRV.displayName == "개역개정")
    }

    // MARK: - 참조

    @Test("장 참조")
    func chapterReference() {
        let reference = BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1))

        #expect(reference.text(locale: Self.korean) == "창세기 1장")
        #expect(reference.text(locale: Self.english) == "Genesis 1")
    }

    @Test("절 참조")
    func verseReference() {
        let reference = BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1), verse: 1)

        #expect(reference.text(locale: Self.korean) == "창세기 1장 1절")
        #expect(reference.text(locale: Self.english) == "Genesis 1:1")
    }

    @Test("절 범위 참조")
    func verseRangeReference() {
        let reference = BibleReference(title: .deuteronomy, chapter: 6, verses: .range(18...19))

        #expect(reference.text(locale: Self.korean) == "신명기 6장 18-19절")
        #expect(reference.text(locale: Self.english) == "Deuteronomy 6:18-19")
    }

    @Test("처음과 끝이 같은 범위는 절 하나로 적는다")
    func singleVerseRangeIsWrittenAsVerse() {
        let reference = BibleReference(title: .deuteronomy, chapter: 6, verses: .range(18...18))

        #expect(reference.text(locale: Self.korean) == "신명기 6장 18절")
        #expect(reference.text(locale: Self.english) == "Deuteronomy 6:18")
    }

    @Test("영어 시편 참조는 단수 Psalm 이고 한국어는 지금 표기 그대로다")
    func psalmReferenceIsSingularInEnglish() {
        let chapter = BibleChapter(title: .psalms, chapter: 23)

        #expect(BibleReference(chapter: chapter).text(locale: Self.korean) == "시편 23장")
        #expect(BibleReference(chapter: chapter).text(locale: Self.english) == "Psalm 23")
        #expect(BibleReference(chapter: chapter, verse: 1).text(locale: Self.korean) == "시편 23장 1절")
        #expect(BibleReference(chapter: chapter, verse: 1).text(locale: Self.english) == "Psalm 23:1")
        #expect(BibleReference(title: .psalms, chapter: 119, verses: .range(1...8)).text(locale: Self.korean) == "시편 119장 1-8절")
        #expect(BibleReference(title: .psalms, chapter: 119, verses: .range(1...8)).text(locale: Self.english) == "Psalm 119:1-8")
    }

    @Test("번호 있는 권 참조")
    func numberedBookReference() {
        let reference = BibleReference(chapter: BibleChapter(title: .samuel1, chapter: 3), verse: 10)

        #expect(reference.text(locale: Self.korean) == "사무엘상 3장 10절")
        #expect(reference.text(locale: Self.english) == "1 Samuel 3:10")
    }

    // MARK: - 번역본 약칭

    @Test("약칭은 참조 뒤에 「 · 약칭」 으로 붙고, 권 이름은 번역본이 아니라 앱 언어를 따른다")
    func translationAbbreviationIsAppendedAfterReference() {
        let kjv = BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 1, showsTranslation: true)
        let nkrv = BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1), verse: 1, showsTranslation: true)
        let bsbChapter = BibleReference(chapter: BibleChapter(title: .psalms, chapter: 23, translation: .BSB), showsTranslation: true)

        #expect(kjv.text(locale: Self.korean) == "창세기 1장 1절 · KJV")
        #expect(kjv.text(locale: Self.english) == "Genesis 1:1 · KJV")
        #expect(nkrv.text(locale: Self.korean) == "창세기 1장 1절 · 개역개정")
        #expect(nkrv.text(locale: Self.english) == "Genesis 1:1 · NKRV")
        #expect(bsbChapter.text(locale: Self.english) == "Psalm 23 · BSB")
    }

    @Test("약칭을 요청하지 않으면 장의 번역본이 있어도 붙이지 않는다")
    func translationIsOmittedUnlessRequested() {
        let reference = BibleReference(chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 1)

        #expect(reference.translation == nil)
        #expect(reference.text(locale: Self.english) == "Genesis 1:1")
    }
}
