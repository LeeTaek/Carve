//
//  SettingsSidebarSelectionTesting.swift
//  SettingsFeatureTest
//
//  설정 사이드바 — 상세 화면의 상태가 바뀌어도 행 선택 표시를 유지한다.
//

@testable import SettingsFeature
import Foundation
import Testing

import ComposableArchitecture

@Suite("설정 사이드바 선택")
@MainActor
struct SettingsSidebarSelectionTesting {
    /// 사이드바 `List(selection:)` 은 선택 값을 행의 값과 비교해 선택을 표시한다. 예전에는 경로 상태를 그대로 썼기 때문에
    /// 상세 화면의 상태가 바뀌는 순간(필사 캔버스 토글 · 광고 제거 상품 불러오기) 행의 값(`.canvas(.initialState)`)과 달라져
    /// 선택 표시가 풀렸다(2026-09-15 시뮬레이터에서 확인).
    @Test("상세 화면의 상태가 바뀌어도 사이드바는 같은 행을 선택한 채로 둔다")
    func detailStateChangeKeepsSelection() async throws {
        let suite = "SettingsSidebarSelectionTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .canvas(.initialState))) {
            SettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }
        var toggled = CanvasSettingsFeature.State()
        toggled.isSingleCanvasEnabled.toggle()

        await store.send(.path(.presented(.canvas(.view(.setSingleCanvasEnabled(toggled.isSingleCanvasEnabled)))))) {
            $0.path = .canvas(toggled)
        }
        // 경로 상태는 더 이상 행을 처음 열 때의 값과 같지 않다 — 그래도 선택은 같은 행이다.
        #expect(store.state.path != .canvas(.initialState))
        #expect(store.state.selectedSidebarItem == .canvas)
    }

    @Test("보고 있는 화면의 행을 다시 골라도 상세 상태를 처음으로 되돌리지 않는다")
    func reselectingCurrentRowKeepsDetailState() async {
        var purchased = RemoveAdsFeature.State()
        purchased.isAdFree = true

        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .removeAds(purchased))) {
            SettingsFeature()
        }

        // 상태가 바뀌면 TestStore 가 실패한다.
        await store.send(.selectSidebarItem(.removeAds))
        #expect(store.state.selectedSidebarItem == .removeAds)
    }

    @Test("다른 행을 고르면 그 화면을 처음 상태로 열고, 선택이 없어지면 상세를 비운다")
    func selectingAnotherRowOpensInitialState() async {
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .iCloud(.initialState))) {
            SettingsFeature()
        }

        await store.send(.selectSidebarItem(.appearance)) {
            $0.path = .appearance(.initialState)
        }
        #expect(store.state.selectedSidebarItem == .appearance)

        await store.send(.selectSidebarItem(nil)) {
            $0.path = nil
        }
        #expect(store.state.selectedSidebarItem == nil)
    }

    @Test("사이드바 행마다 자기 화면을 연다", arguments: SettingsFeature.SidebarItem.allCases)
    func everyRowOpensItsOwnScreen(item: SettingsFeature.SidebarItem) {
        #expect(item.initialPath.sidebarItem == item)
    }
}
