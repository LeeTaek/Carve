//
//  AppCoordinatorNavigationTesting.swift
//  CarveAppTest
//
//  필사 화면에서 다른 화면으로 — 설정(필사 화면 위 패널) · 차트와 즐겨찾기(쌓인 화면) · 패치노트, 그리고 그 화면들이 필사 화면으로 돌려보내는 액션.
//  자식 화면은 서로를 모른다. 코디네이터가 자식의 위임 액션을 받아 화면을 바꾸고, 필사 화면에 장 · 절 이동을 보낸다.
//

import CarveFeature
import ChartFeature
import Domain
import Foundation
import SettingsFeature
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 필사 화면과 다른 화면 사이")
@MainActor
struct AppCoordinatorNavigationTesting {
    private static let verse = BibleVerse(title: BibleChapter(title: .john, chapter: 3), verse: 16, sentence: "하나님이 세상을 이처럼 사랑하사")

    // MARK: 설정

    @Test("필사 화면의 설정 버튼은 설정을 열고, 설정의 「필사로 돌아가기」 는 닫는다")
    func settingsOpenAndClose() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        await store.send(.root(.presented(.carve(.view(.moveToSetting))))) {
            $0.settings = .initialState
        }
        await store.send(.settings(.presented(.view(.backToCarve)))) {
            $0.settings = nil
        }
        #expect(store.state.rootScreen == .carve)
    }

    @Test("절 메뉴 · 도착 안내의 「확인이 필요한 필기」 는 설정을 그 화면으로 열고 탐색 열을 닫는다")
    func draftRecoveryRequestOpensSettings() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())
        let request = AppCoordinatorFeature.Action.root(.presented(.carve(.scope(.carveDetailAction(
            .scope(.chapterCanvasAction(.delegate(.draftRecoveryRequested)))
        )))))

        await store.send(request) {
            $0.settings = SettingsFeature.State.initialState(path: .draftRecovery(.initialState))
        }
        await store.receive(\.root.presented.carve.view.closeNavigationBar)
    }

    @Test("설정 도움말의 「첫 안내 다시 보기」 는 설정을 닫고 필사 화면에 첫 안내를 다시 띄운다")
    func restartFirstRunGuideClosesSettings() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: .initialState(path: .help(.initialState))))

        await store.send(.settings(.presented(.delegate(.restartFirstRunGuide)))) {
            $0.settings = nil
        }
        await store.receive(\.root.presented.carve.view.restartFirstRunGuide)
        #expect(store.state.carve?.firstRunGuide != nil)
    }

    // MARK: 패치노트

    @Test("패치노트의 닫기는 패치노트만 닫는다")
    func patchnoteCloseDismissesPatchnote() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(patchnote: .initialState))

        await store.send(.patchnote(.presented(.delegate(.close)))) {
            $0.patchnote = nil
        }
        #expect(store.state.settings == nil)
    }

    @Test("패치노트의 「도움말 보기」 는 패치노트를 닫고 설정의 도움말을 연다")
    func patchnoteShowHelpOpensSettingsHelp() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(patchnote: .initialState))

        await store.send(.patchnote(.presented(.delegate(.showHelp)))) {
            $0.patchnote = nil
            $0.settings = SettingsFeature.State.initialState(path: .help(.initialState))
        }
    }

    // MARK: 차트 · 즐겨찾기

    @Test("차트 · 즐겨찾기 버튼은 그 화면을 필사 화면 위에 쌓는다")
    func chartAndFavoritesArePushed() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        await store.send(.root(.presented(.carve(.view(.moveToChart)))))
        #expect(store.state.pathScreens == [.chart])

        await store.send(.root(.presented(.carve(.view(.moveToFavorites)))))
        #expect(store.state.pathScreens == [.chart, .favorites])
    }

    @Test("즐겨찾기 「말씀 보러 가기」 · 차트 「필사하러 가기」 는 맨 위 화면을 닫고 탐색 열을 닫는다")
    func backToWritingPopsAndClosesNavigation() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState), .favorites(.initialState)]))

        let favoritesID = try #require(store.state.path.ids.last)
        await store.send(.path(.element(id: favoritesID, action: .favorites(.delegate(.backToWriting)))))
        #expect(store.state.pathScreens == [.chart])
        await store.receive(\.root.presented.carve.view.closeNavigationBar)

        let chartID = try #require(store.state.path.ids.last)
        await store.send(.path(.element(id: chartID, action: .chart(.delegate(.backToWriting)))))
        #expect(store.state.pathScreens.isEmpty)
        await store.receive(\.root.presented.carve.view.closeNavigationBar)
    }

    @Test("즐겨찾기의 「말씀으로 이동」 은 목록을 닫고 그 절로 간다")
    func favoritesOpenVerseMovesToVerse() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.favorites(.initialState)]))
        let favoritesID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: favoritesID, action: .favorites(.delegate(.openVerse(Self.verse))))))
        #expect(store.state.pathScreens.isEmpty)
        await store.receive(\.root.presented.carve.moveToVerse, Self.verse)
        await store.finish()
    }

    @Test("즐겨찾기 목록에서 즐겨찾기가 바뀌면 목록은 둔 채 필사 화면의 별 표시를 다시 읽게 한다")
    func favoritesChangedRefreshesWriting() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.favorites(.initialState)]))
        let favoritesID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: favoritesID, action: .favorites(.delegate(.favoritesChanged)))))
        #expect(store.state.pathScreens == [.favorites])
        await store.receive(\.root.presented.carve.refreshFavorites)
    }

    // MARK: 주간 요약

    @Test("주간 요약에서 장을 고르면 차트를 닫고 그 장으로 간다")
    func weeklySummaryOpenChapterMovesToChapter() async throws {
        let chapter = BibleChapter(title: .psalms, chapter: 119)
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState)]))
        let chartID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: chartID, action: .chart(.drawingWeeklySummary(.openChapter(chapter))))))
        #expect(store.state.pathScreens.isEmpty)
        await store.receive(\.root.presented.carve.moveToChapter, chapter)
        await store.finish()
    }

    @Test("주간 요약에서 최근 필사한 절을 고르면 차트를 닫고 그 절로 간다")
    func weeklySummaryOpenVerseMovesToVerse() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState)]))
        let chartID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: chartID, action: .chart(.drawingWeeklySummary(.openVerse(Self.verse))))))
        #expect(store.state.pathScreens.isEmpty)
        await store.receive(\.root.presented.carve.moveToVerse, Self.verse)
        await store.finish()
    }
}
