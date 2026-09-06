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

        await store.send(.view(.onAppear))   // 기본 off
        await store.send(.view(.setSingleCanvasEnabled(true))) {
            $0.isSingleCanvasEnabled = true
        }
        #expect(defaults.bool(forKey: SingleCanvasFlag.appStorageKey))

        // 밖에서 바뀐 값(defaults write)도 다시 나타날 때 읽는다.
        defaults.set(false, forKey: SingleCanvasFlag.appStorageKey)
        await store.send(.view(.onAppear)) {
            $0.isSingleCanvasEnabled = false
        }
    }
}
