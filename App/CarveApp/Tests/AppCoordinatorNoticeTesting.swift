//
//  AppCoordinatorNoticeTesting.swift
//  CarveAppTest
//
//  필사 화면 위의 두 안내 — 재실행 안내(보류한 실행이 다시 열면 연결될 때)와 연결 전 필기 안내. 둘 다 실행마다 한 번이다.
//

import Domain
import Foundation
import SettingsFeature
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 재실행 · 연결 전 필기 안내")
@MainActor
struct AppCoordinatorNoticeTesting {
    @Test("재실행 안내는 다시 열면 연결되는 환경에서만 띄우고, 닫으면 이 실행에서 다시 띄우지 않는다")
    func relaunchGuidanceShowsOncePerLaunch() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        // 연결을 보류하지 않은 환경 — 다시 열어도 달라지지 않으므로 안내하지 않는다.
        await store.send(.connectionEnvironmentChanged(.ownedForTesting))
        #expect(!store.state.showsRelaunchGuidance)

        await store.send(.connectionEnvironmentChanged(CoordinatorFixture.relaunchable)) {
            $0.showsRelaunchGuidance = true
            $0.didShowRelaunchGuidance = true
        }
        await store.send(.relaunchGuidanceDismissed) {
            $0.showsRelaunchGuidance = false
        }
        await store.send(.connectionEnvironmentChanged(CoordinatorFixture.relaunchable))
        #expect(!store.state.showsRelaunchGuidance)
    }

    @Test("연결 전 필기 안내는 실행마다 한 번 — 「나중에」 로 닫으면 이 실행에서 다시 띄우지 않는다")
    func beforeConnectionNoticeShowsOncePerLaunch() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        await store.send(.beforeConnectionDraftsFound(3)) {
            $0.beforeConnectionNotice = 3
            $0.didShowBeforeConnectionNotice = true
        }
        await store.send(.beforeConnectionNoticeDismissed) {
            $0.beforeConnectionNotice = nil
        }
        await store.send(.beforeConnectionDraftsFound(5))
        #expect(store.state.beforeConnectionNotice == nil)
        #expect(store.state.settings == nil)
    }

    @Test("연결 전 필기 안내의 「필기 확인하기」 는 안내를 내리고 설정의 「확인이 필요한 필기」 를 열며 탐색 열을 닫는다")
    func beforeConnectionReviewOpensDraftRecovery() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        await store.send(.beforeConnectionDraftsFound(2)) {
            $0.beforeConnectionNotice = 2
            $0.didShowBeforeConnectionNotice = true
        }
        await store.send(.beforeConnectionNoticeReviewTapped) {
            $0.beforeConnectionNotice = nil
            $0.settings = SettingsFeature.State.initialState(path: .draftRecovery(.initialState))
        }
        await store.receive(\.root.presented.carve.view.closeNavigationBar)
    }
}
