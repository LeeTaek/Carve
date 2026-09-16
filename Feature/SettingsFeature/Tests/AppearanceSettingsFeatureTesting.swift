//
//  AppearanceSettingsFeatureTesting.swift
//  SettingsFeatureTest
//
//  화면 모드 설정 — 시스템 설정 · 라이트 · 다크.
//

@testable import SettingsFeature
import ClientInterfaces
import Foundation
import Testing

import ComposableArchitecture

@Suite("화면 모드 설정")
@MainActor
struct AppearanceSettingsFeatureTesting {
    @Test("고른 모드는 앱 루트 화면이 읽는 키에 쓴다 — 시스템 설정으로 돌아가는 것도 값으로 저장한다")
    func selectionWritesSharedKey() async throws {
        let suite = "AppearanceSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TestStore(initialState: AppearanceSettingsFeature.State()) {
            AppearanceSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        await store.send(.view(.setAppearanceMode(.dark)))
        #expect(rootAppearanceMode(in: defaults) == .dark)
        // ⚠️ 키와 원시값은 저장 형식이다 — 바뀌면 업데이트한 사용자가 고른 값을 잃는다.
        #expect(defaults.string(forKey: "appearanceMode") == "dark")

        await store.send(.view(.setAppearanceMode(.system)))
        #expect(rootAppearanceMode(in: defaults) == .system)
        #expect(defaults.string(forKey: "appearanceMode") == "system")
    }

    @Test("고른 적 없는 사용자는 시스템 설정을 따른다")
    func untouchedModeFollowsSystem() throws {
        let suite = "AppearanceSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(rootAppearanceMode(in: defaults) == .system)
    }

    @Test("알아볼 수 없는 저장값은 시스템 설정으로 본다")
    func unknownStoredValueFollowsSystem() throws {
        let suite = "AppearanceSettingsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("sepia", forKey: "appearanceMode")

        #expect(rootAppearanceMode(in: defaults) == .system)
    }

    /// 앱 루트 화면(`AppCoordinatorView`)과 같은 키로 읽는다. 매번 새로 읽어 저장된 값을 본다.
    private func rootAppearanceMode(in defaults: UserDefaults) -> AppearanceMode {
        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            SharedReader<AppearanceMode>(.appearanceMode).wrappedValue
        }
    }
}
