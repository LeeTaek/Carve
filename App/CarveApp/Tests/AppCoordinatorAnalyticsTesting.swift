//
//  AppCoordinatorAnalyticsTesting.swift
//  CarveAppTest
//
//  화면 키(`currentScreenKey`)가 바뀔 때마다 analytics 에 화면을 보낸다. 키는 설정 → 쌓인 화면의 맨 위 → 루트 순으로 정한다.
//  화면 전송은 효과에서 하므로 단계마다 효과가 끝나기를 기다린 뒤 본다 — 보낸 순서가 섞이지 않는다.
//

import ClientInterfaces
import Foundation
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 화면 전송")
@MainActor
struct AppCoordinatorAnalyticsTesting {
    @Test("화면 키가 바뀔 때마다 그 화면을 하나씩 보낸다 — 시작 → 필사 → 설정 → 필사 → 차트 → 필사")
    func screenKeyChangesAreSent() async throws {
        let analytics = AnalyticsRecorder()
        let store = makeCoordinatorStore(CoordinatorFixture.launching(), analytics: analytics)
        #expect(store.state.currentScreenKey == "LaunchProgress")

        await store.send(.root(.presented(.launchProgress(.syncCompleted))))
        await store.finish()
        #expect(analytics.screenNames == ["Carve"])
        #expect(analytics.screens.value.last?.parameters == [
            "screen_name": .string("Carve"),
            "screen_class": .string("AppCoordinator")
        ])

        await store.send(.root(.presented(.carve(.view(.moveToSetting)))))
        await store.finish()
        #expect(analytics.screenNames == ["Carve", "Settings"])

        await store.send(.settings(.presented(.view(.backToCarve))))
        await store.finish()
        #expect(analytics.screenNames == ["Carve", "Settings", "Carve"])

        await store.send(.root(.presented(.carve(.view(.moveToChart)))))
        await store.finish()
        #expect(analytics.screenNames == ["Carve", "Settings", "Carve", "Chart"])

        let chartID = try #require(store.state.path.ids.last)
        await store.send(.path(.element(id: chartID, action: .chart(.delegate(.backToWriting)))))
        await store.finish()
        #expect(analytics.screenNames == ["Carve", "Settings", "Carve", "Chart", "Carve"])
    }

    @Test("화면 키가 그대로인 액션은 보내지 않는다")
    func unchangedScreenKeyIsNotSent() async {
        let analytics = AnalyticsRecorder()
        let store = makeCoordinatorStore(CoordinatorFixture.writing(), analytics: analytics)

        await store.send(.beforeConnectionDraftsFound(2))
        await store.send(.beforeConnectionNoticeDismissed)
        await store.send(.root(.presented(.carve(.view(.closeNavigationBar)))))
        await store.finish()

        #expect(store.state.currentScreenKey == "Carve")
        #expect(analytics.screens.value.isEmpty)
    }
}
