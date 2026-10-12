//
//  CarveFeatureEnglishCopyTesting.swift
//  CarveFeatureTest
//
//  영어 현지화(결정 3 · 5 · 8 · 11) — CarveFeature 화면 문구가 영어 로케일에서 카탈로그의 영어로 나오는지.
//  시험은 ko-KR 로 돈다(결정 6). 영어는 로케일을 받는 경로(`…(locale:)`)로 언어를 실제로 골라 본다 —
//  `String(localized:bundle:locale:)` 의 locale 은 언어를 고르지 않는다. 같은 함수의 한국어(로케일 없음) 결과도 함께 본다.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("영어 현지화 — CarveFeature 화면 문구")
@MainActor
struct CarveFeatureEnglishCopyTesting {
    private static let english = Locale(identifier: "en")
    private static let kjvGenesis = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
    private static let nkrvMatthew = BibleChapter(title: .matthew, chapter: 5)

    // MARK: 헤더

    @Test("헤더 제목 · 부제 · VoiceOver 이름은 앱 언어를 따른다 — 영어는 「Genesis 1」, 시편은 단수 「Psalm」")
    func headerReference() {
        #expect(HeaderView.titleText(Self.kjvGenesis, locale: Self.english) == "Genesis 1")
        #expect(HeaderView.titleText(BibleChapter(title: .psalms, chapter: 23), locale: Self.english) == "Psalm 23")
        #expect(HeaderView.subtitleText(Self.kjvGenesis, locale: Self.english) == "KJV · Old Testament / Genesis")
        #expect(HeaderView.subtitleText(Self.nkrvMatthew, locale: Self.english) == "NKRV · New Testament / Matthew")
        #expect(HeaderView.titleAccessibilityLabel(Self.kjvGenesis, locale: Self.english) == "Genesis 1, open book and chapter list")

        // 한국어 기기는 KJV 를 봐도 「창세기 1장」 이다(결정 3).
        #expect(HeaderView.titleText(Self.kjvGenesis) == "창세기 1장")
        #expect(HeaderView.subtitleText(Self.kjvGenesis) == "KJV · 구약 / 창세기")
        #expect(HeaderView.subtitleText(Self.nkrvMatthew) == "개역개정 · 신약 / 마태복음")
        #expect(HeaderView.titleAccessibilityLabel(Self.kjvGenesis) == "창세기 1장, 성경과 장 목록 열기")
    }

    // MARK: 성경 탐색

    @Test("장 목록 제목 · 권 행 VoiceOver 이름은 앱 언어를 따르고, 장 수는 복수형을 고른다")
    func navigationTitles() {
        #expect(CarveNavigationView.chapterListTitle(.genesis, chapter: 1, locale: Self.english) == "Genesis 1")
        #expect(CarveNavigationView.chapterListTitle(.genesis, chapter: nil, locale: Self.english) == "Genesis")
        #expect(CarveNavigationView.chapterListTitle(.genesis, chapter: 1) == "창세기 1장")

        #expect(CarveNavigationView.titleAccessibilityLabel(.genesis, isSelected: true, locale: Self.english) == "Genesis, 50 chapters")
        #expect(CarveNavigationView.titleAccessibilityLabel(.obadiah, isSelected: true, locale: Self.english) == "Obadiah, 1 chapter")
        #expect(CarveNavigationView.titleAccessibilityLabel(.genesis, isSelected: false, locale: Self.english) == "Genesis")
        #expect(CarveNavigationView.titleAccessibilityLabel(.genesis, isSelected: true) == "창세기, 총 50장")
    }

    @Test("권 검색은 앱 언어와 상관없이 한국어 · 영어 이름 어느 쪽으로도 맞는다")
    func titleSearchMatchesBothLanguages() {
        #expect(CarveNavigationView.titleMatches(.genesis, searchText: "창세"))
        #expect(CarveNavigationView.titleMatches(.genesis, searchText: "gen"))
        #expect(CarveNavigationView.titleMatches(.samuel1, searchText: "1 Sam"))
        #expect(!CarveNavigationView.titleMatches(.genesis, searchText: "출애굽"))
    }

    // MARK: 이미지 출처

    @Test("이미지 출처는 영어 기기에서 「Genesis 1:1 · KJV」 다")
    func verseImageReference() {
        #expect(VerseImageContent.reference(chapter: Self.kjvGenesis, verse: 1, locale: Self.english) == "Genesis 1:1 · KJV")
        #expect(VerseImageContent.reference(chapter: Self.kjvGenesis, verse: 1) == "창세기 1장 1절 · KJV")
    }

    // MARK: 즐겨찾기 날짜

    @Test("즐겨찾기 추가 날짜는 기기 로케일의 날짜 서식을 따른다 — 영어는 「Added September 15」, 다른 해는 연도까지")
    func favoriteAddedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)))
        let thisYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9)))
        let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23)))

        #expect(FavoriteListView.addedDateText(thisYear, now: now, calendar: calendar, locale: Self.english) == "Added September 15")
        #expect(FavoriteListView.addedDateText(lastYear, now: now, calendar: calendar, locale: Self.english) == "Added December 31, 2025")
        #expect(FavoriteListView.addedDateText(thisYear, now: now, calendar: calendar, locale: Locale(identifier: "ko")) == "9월 15일 추가")
    }

    @Test("이전 필사 날짜도 고정 ko_KR 형식이 아니라 로케일 서식이다")
    func historyDate() throws {
        let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 15, hour: 12
        )))
        let english = VerseDrawingHistoryView.dateText(date, locale: Self.english)
        #expect(english.contains("September"))
        #expect(english.contains("2026"))
        #expect(VerseDrawingHistoryView.dateText(nil, locale: Self.english) == "Unknown date")
        #expect(VerseDrawingHistoryView.dateText(nil) == "날짜를 확인할 수 없어요")
    }

    // MARK: 지우기 확인

    @Test("지우기 확인창은 영어 기기에서 참조 · 문구 · 버튼이 모두 영어다")
    func eraseConfirmation() throws {
        let confirm = ChapterCanvasFeature.confirmEraseAlert(chapter: Self.kjvGenesis, verse: 1, locale: Self.english)
        #expect(String(state: confirm.title) == "Erase writing on Genesis 1:1")
        let message = String(state: try #require(confirm.message))
        #expect(message.hasPrefix("Erase your writing on this verse?"))
        #expect(message.hasSuffix("Undo history for this chapter will be cleared."))
        #expect(confirm.buttons.map { String(state: $0.label) } == ["Cancel", "Erase"])

        let failure = ChapterCanvasFeature.eraseFailureAlert(chapter: Self.kjvGenesis, verse: 1, locale: Self.english)
        #expect(String(state: failure.title) == "Couldn't erase the writing")
        #expect(String(state: try #require(failure.message)) == "Your writing on Genesis 1:1 is unchanged. Please try again.")
        #expect(failure.buttons.map { String(state: $0.label) } == ["Close", "Try Again"])

        // 한국어(로케일 없음)는 예전 문구 그대로다.
        let korean = ChapterCanvasFeature.confirmEraseAlert(chapter: Self.kjvGenesis, verse: 1)
        #expect(String(state: korean.title) == "창세기 1장 1절 필사 지우기")
        #expect(korean.buttons.map { String(state: $0.label) } == ["취소", "지우기"])
    }

    // MARK: 팔레트 · 본문 설정

    @Test("색 이름은 카탈로그의 영어로, 글꼴 이름은 Domain 글꼴 이름(FontCase.title)의 영어로 나온다")
    func paletteAndFontNames() throws {
        let ink = try #require(ColorPalatteFeature.defaultColors.first)
        #expect(ColorPalatteView.colorName(ink, locale: Self.english) == "Ink black")
        #expect(ColorPalatteView.colorName(ink) == "먹색")
        // 글꼴 이름은 Domain 한 곳에서 현지화한다 — 본문 설정 칸과 Domain 표기가 어긋나지 않는다.
        #expect(FontCase.allCases.map { SentenceSettingsView.fontName($0, locale: Self.english) }
            == ["Nanum Myeongjo", "Nanum Gothic", "Nanum Flower Scent"])
        #expect(FontCase.allCases.map { SentenceSettingsView.fontName($0) } == ["나눔명조", "나눔고딕", "나눔손글씨 꽃내음"])
        #expect(FontCase.allCases.map { SentenceSettingsView.fontName($0, locale: Self.english) }
            == FontCase.allCases.map { $0.title(locale: Self.english) })
    }

    // MARK: 앱 이름

    @Test("앱 안 로고의 앱 이름은 영어에서 Carve 다(결정 8)")
    func appName() {
        #expect(CarveFeatureCatalog.string("새기다", locale: Self.english) == "Carve")
        #expect(CarveFeatureCatalog.string("새기다") == "새기다")
    }

    // MARK: 용어

    @Test("영어 용어는 모듈 사이에서 같다 — 이전 필사 = Previous Writing, 확인이 필요한 필기 = Drafts to Review, 본문 설정 = Text Settings")
    func sharedTerms() {
        // 설정 화면 문구(SettingsFeature)가 이 이름들을 「“Previous Writing”」 처럼 인용한다 — 메뉴 이름과 어긋나지 않게 고정한다.
        #expect(CarveFeatureCatalog.string("이전 필사 내용 보기", locale: Self.english) == "Previous Writing")
        #expect(CarveFeatureCatalog.string("확인이 필요한 필기 \(3)", locale: Self.english) == "Drafts to Review (3)")
        #expect(CarveFeatureCatalog.string("필기 확인하기", locale: Self.english) == "Review Drafts")
        #expect(CarveFeatureCatalog.string("본문 설정", locale: Self.english) == "Text Settings")
        #expect(CarveFeatureCatalog.string("손가락 필사 허용", locale: Self.english) == "Allow finger writing")
        #expect(CarveFeatureCatalog.string("지우기", locale: Self.english) == "Erase")
    }
}
