//
//  CanvasSettingsFeatureTesting.swift
//  SettingsFeatureTest
//
//  Phase 3 (3/3) — 단일 Canvas flag 토글 (설계 §10-3 · §13).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("Phase 3 — 필사 캔버스 설정 (3/3)")
@MainActor
struct CanvasSettingsFeatureTesting {
    @Test("토글은 SingleCanvasFlag 키에 쓰고, 화면이 나타날 때 그 키를 읽는다")
    func toggleWritesFlagAndAppearReadsIt() async throws {
        let suite = "CanvasSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TestStore(initialState: CanvasSettingsFeature.State()) {
            CanvasSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        // 키가 없으면 기본값(현재 on)을 보여준다 — 상태가 이미 그 값이라 변화가 없다.
        await store.send(.view(.onAppear))

        // 끄면 키에 false 가 쓰인다.
        await store.send(.view(.setSingleCanvasEnabled(false))) {
            $0.isSingleCanvasEnabled = false
        }
        #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) != nil)
        #expect(defaults.bool(forKey: SingleCanvasFlag.appStorageKey) == false)

        // 밖에서 바뀐 값(defaults write)도 다시 나타날 때 읽는다.
        defaults.set(true, forKey: SingleCanvasFlag.appStorageKey)
        await store.send(.view(.onAppear)) {
            $0.isSingleCanvasEnabled = true
        }
    }

    /// ⚠️ 읽는 쪽이 둘이라 **기본값이 갈라지면 사용자가 모순을 본다** — 앱은 단일 Canvas 로 도는데
    /// 설정 토글만 OFF 로 보이는 상태. `UserDefaults.bool(forKey:)` 가 키 부재를 무조건 false 로
    /// 돌려주기 때문이며, 기본값을 `SingleCanvasFlag` 한 곳에 둬서 막는다 (설계 §10-3).
    @Test("토글을 만진 적 없는 사용자는 설정 화면에서도 기본값을 본다 — bool(forKey:) 의 false 가 아니라")
    func untouchedFlagShowsDefaultNotFalse() async throws {
        let suite = "CanvasSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // given: 키가 없다 — 아직 아무도 토글을 만지지 않았다.
        #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) == nil)
        // 그리고 bool(forKey:) 는 이 상황에서 false 를 준다 — 이것을 그대로 쓰면 안 되는 이유다.
        #expect(defaults.bool(forKey: SingleCanvasFlag.appStorageKey) == false)

        let store = TestStore(initialState: CanvasSettingsFeature.State()) {
            CanvasSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        await store.send(.view(.onAppear))
        #expect(store.state.isSingleCanvasEnabled == SingleCanvasFlag.defaultValue)
    }

    @Test("명시적으로 끈 사용자는 기본값이 켜져 있어도 계속 꺼진 채로 본다 — 롤백이 유지된다")
    func explicitOffSurvivesDefaultOn() async throws {
        let suite = "CanvasSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SingleCanvasFlag.appStorageKey)

        let store = TestStore(initialState: CanvasSettingsFeature.State()) {
            CanvasSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        await store.send(.view(.onAppear)) {
            $0.isSingleCanvasEnabled = false
        }
    }
}
