//
//  AppCoordinatorWidgetTesting.swift
//  CarveAppTest
//
//  위젯을 눌러 앱이 열렸다(`openedURL`). 시작 화면이면 그 절을 잡아 두었다가 필사 화면에 들어간 뒤 옮기고,
//  필사 중이면 설정 · 쌓인 화면을 닫고 곧바로 그 절로 간다.
//

import CarveFeature
import ChartFeature
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
}
