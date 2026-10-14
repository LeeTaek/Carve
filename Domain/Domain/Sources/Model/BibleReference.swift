//
//  BibleReference.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//

import Foundation

/// 장 · 절 참조 문자열(「창세기 1장 1절」 · 「Genesis 1:1」)을 만드는 유일한 곳(영어 현지화 결정 3 · 11).
///
/// | 표기 | ko | en |
/// |---|---|---|
/// | 장 | 창세기 1장 | Genesis 1 |
/// | 절 | 창세기 1장 1절 | Genesis 1:1 |
/// | 절 범위 | 신명기 6장 18-19절 | Deuteronomy 6:18-19 |
/// | 시편 | 시편 23장 1절 | Psalm 23:1(단수 — 권 목록 이름은 「Psalms」) |
/// | 번역본 약칭 | 창세기 1장 1절 · KJV | Genesis 1:1 · KJV |
///
/// - 권 이름 · 장절 표기는 번역본이 아니라 화면 언어를 따른다 — 한국어 화면은 KJV 를 봐도 「창세기 1장 1절」 이다.
///   언어는 늘 부르는 쪽이 locale 로 준다(`text(locale:)` — 뷰는 환경 locale, 리듀서 · 인프라는 `AppLanguage.displayLocale()`).
/// - 형식 문자열은 Domain 카탈로그(`Resources/Localizable.xcstrings`, `DomainCatalog`)에 있다. 호출부에서 문자열을 이어 붙이지 않는다.
/// - 번역본이 섞이는 곳(이미지 · 위젯 · 헤더 · 즐겨찾기 · 최근 기록 · 주간 요약 · 확인이 필요한 필기 · 위젯 설정)은 약칭을 붙인다.
public struct BibleReference: Sendable, Hashable {
    /// 참조가 가리키는 절.
    public enum Verses: Sendable, Hashable {
        /// 장 전체(「창세기 1장」).
        case wholeChapter
        /// 절 하나(「창세기 1장 1절」).
        case verse(Int)
        /// 절 범위(「신명기 6장 18-19절」). 처음과 끝이 같으면 절 하나로 적는다.
        case range(ClosedRange<Int>)
    }

    /// 권.
    public var title: BibleTitle
    /// 장 번호.
    public var chapter: Int
    /// 가리키는 절.
    public var verses: Verses
    /// 참조 뒤에 약칭(「 · KJV」)을 붙일 번역본. nil 이면 붙이지 않는다.
    public var translation: Translation?

    public init(title: BibleTitle, chapter: Int, verses: Verses = .wholeChapter, translation: Translation? = nil) {
        self.title = title
        self.chapter = chapter
        self.verses = verses
        self.translation = translation
    }

    /// 장(번역본 포함)으로 참조를 만든다.
    /// - Parameters:
    ///   - chapter: 권 · 장 · 번역본.
    ///   - verses: 가리키는 절. 기본은 장 전체.
    ///   - showsTranslation: true 면 장의 번역본 약칭을 붙인다.
    public init(chapter: BibleChapter, verses: Verses = .wholeChapter, showsTranslation: Bool = false) {
        self.init(
            title: chapter.title,
            chapter: chapter.chapter,
            verses: verses,
            translation: showsTranslation ? chapter.translation : nil
        )
    }

    /// 장의 절 하나를 가리키는 참조를 만든다(「창세기 1장 1절」).
    public init(chapter: BibleChapter, verse: Int, showsTranslation: Bool = false) {
        self.init(chapter: chapter, verses: .verse(verse), showsTranslation: showsTranslation)
    }

    /// 역할: 참조 문자열을 한 언어로 만든다.
    /// 입력 · 출력: 로케일(뷰는 환경 locale, 리듀서 · 인프라는 `AppLanguage.displayLocale()`) → 「창세기 1장 1절 · KJV」 · 「Genesis 1:1 · KJV」 같은 문자열.
    /// 부작용: 없음.
    public func text(locale: Locale) -> String {
        let reference = referenceText(locale: locale)
        guard let translation else { return reference }
        return reference + " · " + translation.displayName(locale: locale)
    }

    /// 약칭 없는 참조. 시편은 en 에서 단수 「Psalm」 이라 형식 문자열을 따로 둔다.
    private func referenceText(locale: Locale) -> String {
        let isPsalm = title == .psalms
        switch verses {
        case .wholeChapter:
            if isPsalm { return DomainCatalog.string("시편 \(chapter)장", locale: locale) }
            return DomainCatalog.string("\(title.localizedName(locale: locale)) \(chapter)장", locale: locale)
        case .verse(let verse):
            if isPsalm { return DomainCatalog.string("시편 \(chapter)장 \(verse)절", locale: locale) }
            return DomainCatalog.string("\(title.localizedName(locale: locale)) \(chapter)장 \(verse)절", locale: locale)
        case .range(let range) where range.lowerBound == range.upperBound:
            return Self(title: title, chapter: chapter, verses: .verse(range.lowerBound)).referenceText(locale: locale)
        case .range(let range):
            let (first, last) = (range.lowerBound, range.upperBound)
            if isPsalm { return DomainCatalog.string("시편 \(chapter)장 \(first)-\(last)절", locale: locale) }
            return DomainCatalog.string("\(title.localizedName(locale: locale)) \(chapter)장 \(first)-\(last)절", locale: locale)
        }
    }
}
