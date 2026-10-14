//
//  BibleChapterTranslationTesting.swift
//  DomainTest
//
//  Created by Claude on 10/6/26.
//

@testable import Domain
import Foundation
import Testing

/// 장 식별의 번역본(`BibleChapter.translation`)과 `Translation` 의 멤버를 본다(영어 현지화 결정 4 · 13).
struct BibleChapterTranslationTesting {
    private static let english = Locale(identifier: "en")
    private static let korean = Locale(identifier: "ko")

    // MARK: - Codable

    @Test("translation 키가 없는 옛 JSON 은 개역개정으로 읽는다")
    func legacyJSONWithoutTranslationDecodesAsNKRV() throws {
        // Given — 옛 @Shared("title") · -UITestChapter JSON
        let data = Data(#"{"title":"1-19Psalms.txt","chapter":119}"#.utf8)

        // When
        let chapter = try JSONDecoder().decode(BibleChapter.self, from: data)

        // Then
        #expect(chapter.title == .psalms)
        #expect(chapter.chapter == 119)
        #expect(chapter.translation == .NKRV)
        #expect(chapter == BibleChapter(title: .psalms, chapter: 119))
    }

    @Test("모든 번역본의 장이 JSON 왕복에서 그대로다", arguments: Translation.allCases)
    func chapterRoundTripsThroughJSON(translation: Translation) throws {
        // Given
        let chapter = BibleChapter(title: .john, chapter: 3, translation: translation)

        // When
        let decoded = try JSONDecoder().decode(BibleChapter.self, from: JSONEncoder().encode(chapter))

        // Then
        #expect(decoded == chapter)
        #expect(decoded.translation == translation)
    }

    @Test("JSON 에는 translation 키를 쓴다 — 구버전은 이 키를 무시하고 권 · 장을 읽는다")
    func encodedJSONCarriesTranslationKey() throws {
        // When
        let data = try JSONEncoder().encode(BibleChapter(title: .genesis, chapter: 1, translation: .KJV))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Then
        #expect(object["title"] as? String == "1-01Genesis.txt")
        #expect(object["chapter"] as? Int == 1)
        #expect(object["translation"] as? String == "KJV")
    }

    // MARK: - 같음 · 해시

    @Test("== 와 해시는 번역본까지 구분한다")
    func equalityAndHashDistinguishTranslation() {
        // Given — 같은 권 · 장, 다른 번역본
        let chapters = Translation.allCases.map { BibleChapter(title: .genesis, chapter: 1, translation: $0) }

        // Then
        #expect(chapters[0] != chapters[1])
        #expect(chapters[1] != chapters[2])
        #expect(Set(chapters).count == Translation.allCases.count)
        #expect(BibleChapter(title: .genesis, chapter: 1, translation: .KJV) == BibleChapter(title: .genesis, chapter: 1, translation: .KJV))
        #expect(BibleChapter(title: .genesis, chapter: 1) != BibleChapter(title: .genesis, chapter: 2))
        #expect(BibleChapter(title: .genesis, chapter: 1) != BibleChapter(title: .exodus, chapter: 1))
    }

    @Test("번역본을 주지 않은 장 · initialState 는 개역개정이다")
    func defaultTranslationIsNKRV() {
        #expect(BibleChapter(title: .genesis, chapter: 1).translation == .NKRV)
        #expect(BibleChapter.initialState == BibleChapter(title: .genesis, chapter: 1, translation: .NKRV))
    }

    // MARK: - 처음 설치 기본값

    @Test("첫 언어가 한국어면 개역개정 창세기 1장이다")
    func initialChapterForKoreanIsNKRV() {
        #expect(BibleChapter.initial(preferredLanguages: ["ko-KR"]) == BibleChapter(title: .genesis, chapter: 1, translation: .NKRV))
        #expect(BibleChapter.initial(preferredLanguages: ["ko"]) == BibleChapter(title: .genesis, chapter: 1, translation: .NKRV))
        #expect(BibleChapter.initial(preferredLanguages: ["ko-Kore-KR", "en-US"]).translation == .NKRV)
    }

    @Test("첫 언어가 한국어가 아니거나 목록이 비면 BSB 창세기 1장이다")
    func initialChapterForOthersIsBSB() {
        #expect(BibleChapter.initial(preferredLanguages: ["en-US"]) == BibleChapter(title: .genesis, chapter: 1, translation: .BSB))
        #expect(BibleChapter.initial(preferredLanguages: []) == BibleChapter(title: .genesis, chapter: 1, translation: .BSB))
        #expect(BibleChapter.initial(preferredLanguages: ["ja-JP"]).translation == .BSB)
        // 첫 언어만 본다
        #expect(BibleChapter.initial(preferredLanguages: ["en-US", "ko-KR"]).translation == .BSB)
    }

    // MARK: - Translation

    @Test("번역본은 개역개정 · KJV · BSB 순서다")
    func translationCasesAreNKRVKJVBSB() {
        #expect(Translation.allCases == [.NKRV, .KJV, .BSB])
        #expect(Translation.allCases.map(\.rawValue) == ["NKRV", "KJV", "BSB"])
    }

    @Test("약칭은 개역개정만 현지화하고 KJV · BSB 는 그대로다")
    func displayNameIsLocalizedOnlyForNKRV() {
        #expect(Translation.NKRV.displayName(locale: Self.korean) == "개역개정")
        #expect(Translation.NKRV.displayName(locale: Self.english) == "NKRV")
        for locale in [Self.korean, Self.english] {
            #expect(Translation.KJV.displayName(locale: locale) == "KJV")
            #expect(Translation.BSB.displayName(locale: locale) == "BSB")
        }
    }

    @Test("전체 이름은 개역개정만 현지화하고 KJV · BSB 는 영어 이름이다")
    func fullNameIsLocalizedOnlyForNKRV() {
        #expect(Translation.NKRV.fullName(locale: Self.korean) == "개역개정")
        #expect(Translation.NKRV.fullName(locale: Self.english) == "New Korean Revised Version")
        for locale in [Self.korean, Self.english] {
            #expect(Translation.KJV.fullName(locale: locale) == "King James Version")
            #expect(Translation.BSB.fullName(locale: locale) == "Berean Standard Bible")
        }
    }

    @Test("본문 리소스 파일 이름은 개역개정은 rawValue, 영어는 번역본 접두를 붙인다")
    func resourceFileNameFollowsTranslation() {
        #expect(Translation.NKRV.resourceFileName(for: .genesis) == "1-01Genesis.txt")
        #expect(Translation.KJV.resourceFileName(for: .genesis) == "KJV-1-01Genesis.txt")
        #expect(Translation.BSB.resourceFileName(for: .john3) == "BSB-2-25John3.txt")
    }

    @Test("본문 인코딩 · 언어 코드는 개역개정 CP949 · ko, 영어 UTF-8 · en 이다")
    func textEncodingAndLanguageCodeFollowTranslation() {
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0422))
        #expect(Translation.NKRV.textEncoding == cp949)
        #expect(Translation.KJV.textEncoding == .utf8)
        #expect(Translation.BSB.textEncoding == .utf8)
        #expect(Translation.NKRV.languageCode == "ko")
        #expect(Translation.KJV.languageCode == "en")
        #expect(Translation.BSB.languageCode == "en")
    }
}
