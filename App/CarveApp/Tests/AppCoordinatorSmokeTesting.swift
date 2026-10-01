//
//  AppCoordinatorSmokeTesting.swift
//  CarveAppTest
//
//  Created by Claude on 9/30/26.
//

import Foundation
import Testing

/// `CarveAppTest` 는 호스트 앱 없이 코디네이터 소스를 함께 컴파일해 돈다. 그 구성이 살아 있는지 보는 연기 시험이다.
struct AppCoordinatorSmokeTesting {
    @Test("호스트 앱 없이 코디네이터 초기 상태를 만든다 — 시작 화면에서 출발하고 다른 화면은 닫혀 있다")
    func initialStateStartsAtLaunchProgress() {
        // 앱은 `Store(initialState: .initialState)` 로 시작한다.
        let state = AppCoordinatorFeature.State.initialState

        guard case .launchProgress(let launch)? = state.root else {
            Issue.record("루트가 시작 화면이 아니다: \(String(describing: state.root))")
            return
        }
        #expect(launch.mode == nil)
        #expect(launch.startedFirst == false)
        #expect(state.path.isEmpty)
        #expect(state.settings == nil)
        #expect(state.patchnote == nil)
        #expect(state.showsRelaunchGuidance == false)
        #expect(state.beforeConnectionNotice == nil)
        #expect(state.pendingWidgetVerse == nil)
        #expect(state.currentScreenKey == "LaunchProgress")
        // 호스트 앱이 없다 — 이 번들을 띄운 쪽은 앱(kr.co.carve.leetaek)이 아니라 테스트 러너다.
        #expect(Bundle.main.bundleIdentifier != "kr.co.carve.leetaek")
    }
}
