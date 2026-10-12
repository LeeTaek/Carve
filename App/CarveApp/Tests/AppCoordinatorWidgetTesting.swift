//
//  AppCoordinatorWidgetTesting.swift
//  CarveAppTest
//
//  위젯을 눌러 앱이 열렸다(`openedURL`). 시작 화면이면 그 절을 잡아 두었다가 필사 화면에 들어간 뒤 옮기고,
//  필사 중이면 설정 · 쌓인 화면을 닫고 곧바로 그 절로 간다.
//

import CarveFeature
import ChartFeature
import Domain
import Foundation
import SettingsFeature
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 위젯으로 열기")
@MainActor
struct AppCoordinatorWidgetTesting {
    @Test("시작 화면에서 위젯으로 열리면 그 절을 잡아 두었다가, 필사 화면에 들어가며 그 절로 간다")
    func widgetDuringLaunchWaitsForWriting() async throws {
        let url = try #require(CoordinatorFixture.widgetURL)
        let store = makeCoordinatorStore(CoordinatorFixture.launching())

        await store.send(.openedURL(url)) {
            $0.pendingWidgetVerse = CoordinatorFixture.widgetVerse
        }
        #expect(store.state.rootScreen == .launchProgress)

        await store.send(.root(.presented(.launchProgress(.syncCompleted)))) {
            $0.pendingWidgetVerse = nil
        }
        #expect(store.state.rootScreen == .carve)
        await store.receive(\.root.presented.carve.moveToVerse, CoordinatorFixture.widgetVerse)
        await store.finish()
    }

    @Test("필사 중에 위젯으로 열리면 설정과 쌓인 화면을 닫고 곧바로 그 절로 간다")
    func widgetWhileWritingClosesOverlays() async throws {
        let url = try #require(CoordinatorFixture.widgetURL)
        let store = makeCoordinatorStore(
            CoordinatorFixture.writing(settings: .initialState, path: [.chart(.initialState), .favorites(.initialState)])
        )

        await store.send(.openedURL(url)) {
            $0.settings = nil
            $0.pendingWidgetVerse = nil
        }
        #expect(store.state.pathScreens.isEmpty)
        await store.receive(\.root.presented.carve.moveToVerse, CoordinatorFixture.widgetVerse)
        await store.finish()
    }

    @Test("위젯이 만든 URL 이 아니면 떠 있는 화면을 그대로 둔다")
    func unrelatedURLIsIgnored() async throws {
        let url = try #require(URL(string: "https://example.com/verse?title=1-19Psalms.txt&chapter=23&verse=1"))
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: .initialState, path: [.chart(.initialState)]))

        await store.send(.openedURL(url)) {
            $0.settings = .initialState
        }
        #expect(store.state.pathScreens == [.chart])
        #expect(store.state.pendingWidgetVerse == nil)
    }

    // MARK: - 번역본 (영어 현지화 설계 §7)

    @Test("KJV 위젯 링크로 열리면 개역개정이 아니라 KJV 장의 그 절로 간다")
    func kjvWidgetWhileWritingMovesToKJVVerse() async throws {
        let url = try #require(Self.widgetURL(translation: Translation.KJV.rawValue))
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: .initialState))

        await store.send(.openedURL(url)) {
            $0.settings = nil
        }
        await store.receive(\.root.presented.carve.moveToVerse, Self.kjvVerse)
        await store.finish()
    }

    @Test("시작 화면에서 KJV 위젯 링크로 열리면 잡아 둔 절이 번역본을 지키고, 필사 화면에 들어가며 KJV 절로 간다")
    func kjvWidgetDuringLaunchKeepsTranslation() async throws {
        let url = try #require(Self.widgetURL(translation: Translation.KJV.rawValue))
        let store = makeCoordinatorStore(CoordinatorFixture.launching())

        await store.send(.openedURL(url)) {
            $0.pendingWidgetVerse = Self.kjvVerse
        }
        #expect(store.state.pendingWidgetVerse?.title.translation == .KJV)

        await store.send(.root(.presented(.launchProgress(.syncCompleted)))) {
            $0.pendingWidgetVerse = nil
        }
        await store.receive(\.root.presented.carve.moveToVerse, Self.kjvVerse)
        await store.finish()
    }

    @Test("이 판이 모르는 번역본의 위젯 링크는 개역개정으로 바꾸지 않고 무시한다 — 떠 있는 화면도 그대로다")
    func unknownTranslationWidgetIsIgnored() async throws {
        let url = try #require(Self.widgetURL(translation: "ESV"))
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: .initialState, path: [.chart(.initialState)]))

        await store.send(.openedURL(url)) {
            $0.settings = .initialState
        }
        #expect(store.state.pathScreens == [.chart])
        #expect(store.state.pendingWidgetVerse == nil)
        await store.finish()
    }

    @Test("시작 화면에서 모르는 번역본 링크를 받으면 잡아 두지 않는다 — 필사 화면에 들어가도 그 절로 가지 않는다")
    func unknownTranslationWidgetDuringLaunchIsNotHeld() async throws {
        let url = try #require(Self.widgetURL(translation: "ESV"))
        let store = makeCoordinatorStore(CoordinatorFixture.launching())

        await store.send(.openedURL(url))
        #expect(store.state.pendingWidgetVerse == nil)
        await store.send(.root(.presented(.launchProgress(.syncCompleted))))
        #expect(store.state.rootScreen == .carve)
        await store.finish()
    }

    @Test("링크의 번역본을 그대로 장에 담는다 — 아는 번역본만 절이 되고, 모르거나 빠진 번역본은 nil 이다")
    func verseFromURLCarriesTranslation() throws {
        for translation in Translation.allCases {
            let url = try #require(Self.widgetURL(translation: translation.rawValue))
            let verse = try #require(AppCoordinatorFeature.verse(from: url))
            #expect(verse.title == BibleChapter(title: .psalms, chapter: 23, translation: translation))
            #expect(verse.verse == 1)
        }
        let unknown = try #require(Self.widgetURL(translation: "ESV"))
        #expect(AppCoordinatorFeature.verse(from: unknown) == nil)
        let missing = try #require(URL(string: "carve://verse?title=1-19Psalms.txt&chapter=23&verse=1"))
        #expect(AppCoordinatorFeature.verse(from: missing) == nil)
    }

    /// KJV 위젯이 여는 절 — 시편 23편 1절(KJV). 위젯 URL 에는 본문이 없어 빈 문장으로 온다.
    private static let kjvVerse = BibleVerse(title: BibleChapter(title: .psalms, chapter: 23, translation: .KJV), verse: 1, sentence: "")

    /// 시편 23편 1절을 그 번역본으로 담은 위젯 URL(`VerseWidgetPayload.deepLinkURL`). 번역본은 문자열 그대로 링크에 들어간다.
    private static func widgetURL(translation: String) -> URL? {
        VerseWidgetPayload(
            titleRawValue: BibleTitle.psalms.rawValue,
            bookDisplayName: "Psalms",
            chapter: 23,
            verse: 1,
            translation: translation,
            translationDisplayName: translation,
            sentence: "The LORD is my shepherd; I shall not want.",
            designatedAt: Date(timeIntervalSince1970: 0)
        ).deepLinkURL
    }
}
