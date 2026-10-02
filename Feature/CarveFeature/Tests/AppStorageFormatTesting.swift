//
//  AppStorageFormatTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 10/1/26.
//

@testable import CarveFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 설정 키의 저장 형식 — 기본 타입(Bool · Int)은 Sharing 의 `.appStorage` 로 UserDefaults 기본 타입에, Codable 값은
/// `.codableAppStorage` 로 JSON Data 에 둔다. Swift 6.4(Xcode 27)에서 `.appStorage` 가 Codable 키로 해석돼 2.0.0 이
/// 1.x 설정을 읽지 못하고 기본값으로 덮어썼다(2026-10-01 재현). 컴파일러가 바뀌어도 형식이 그대로인지 실제 State 선언으로 고정한다.
@MainActor
struct AppStorageFormatTesting {
    @Test("본문 설정의 왼손잡이 · 손가락 필기는 Bool 로, 본문 모양은 JSON 으로 저장한다")
    func sentenceSettingsStorePlainBools() throws {
        try withSuite { defaults in
            let state = withDependencies { $0.defaultAppStorage = defaults } operation: { SentenceSettingsFeature.State() }
            state.$isLeftHanded.withLock { $0 = true }
            state.$allowFingerDrawing.withLock { $0 = true }

            #expect(defaults.object(forKey: "isLeftHanded") as? Bool == true)
            #expect(defaults.object(forKey: "allowFingerDrawing") as? Bool == true)
            #expect(defaults.object(forKey: SentenceSetting.appStorageKey) is Data)
        }
    }

    @Test("팔레트의 색 · 굵기 선택은 Int 로, 펜 설정 · 색 · 굵기 목록은 JSON 으로 저장한다")
    func paletteStoresPlainIndicesAndCodableLists() throws {
        try withSuite { defaults in
            let state = withDependencies { $0.defaultAppStorage = defaults } operation: { PencilPalatteFeature.State() }
            state.$selectedColorIndex.withLock { $0 = 2 }
            state.$selectedWidthIndex.withLock { $0 = 1 }

            #expect(defaults.object(forKey: "selectedColorIndex") as? Int == 2)
            #expect(defaults.object(forKey: "selectedWidthIndex") as? Int == 1)
            #expect(defaults.object(forKey: "pencilConfig") is Data)
            #expect(defaults.object(forKey: "palatteColorSet") is Data)
            #expect(defaults.object(forKey: "lineWidthSet") is Data)
        }
    }

    @Test("1.x 가 기본 타입으로 남긴 설정을 그대로 읽고 덮어쓰지 않는다 — 업데이트 때 초기화되지 않는다")
    func readsValuesWrittenByOlderVersions() throws {
        try withSuite { defaults in
            defaults.set(true, forKey: "isLeftHanded")
            defaults.set(true, forKey: "allowFingerDrawing")
            defaults.set(2, forKey: "selectedColorIndex")
            defaults.set(1, forKey: "selectedWidthIndex")

            let settings = withDependencies { $0.defaultAppStorage = defaults } operation: { SentenceSettingsFeature.State() }
            let palette = withDependencies { $0.defaultAppStorage = defaults } operation: { PencilPalatteFeature.State() }

            #expect(settings.isLeftHanded)
            #expect(settings.allowFingerDrawing)
            #expect(palette.selectedColorIndex == 2)
            #expect(palette.selectedWidthIndex == 1)
            #expect(defaults.object(forKey: "isLeftHanded") as? Bool == true)
            #expect(defaults.object(forKey: "selectedColorIndex") as? Int == 2)
        }
    }

    /// `CarveNavigationFeature` 와 같은 선언을 쓴다 — 그 State 는 다른 화면의 공유 초기 상태를 품고 있어 시험 저장소로 따로 만들 수 없다.
    /// 2.0.x 의 단일 Canvas flag 키(`"singleCanvasEnabled"`)는 2.1 에서 flag 를 지운 뒤에도 N-Canvas 제거 안내가 UserDefaults 로 직접 Bool 로 읽는다.
    @Test("첫 실행 안내 · 단일 Canvas flag 는 Bool 로 저장해 설정 화면의 UserDefaults 직접 읽기와 맞는다")
    func flagsMatchDirectUserDefaultsAccess() throws {
        try withSuite { defaults in
            withDependencies { $0.defaultAppStorage = defaults } operation: {
                @Shared(.appStorage("hasSeenFirstRunGuide")) var hasSeenFirstRunGuide = false
                @Shared(.appStorage("singleCanvasEnabled")) var isSingleCanvasEnabled = true
                $hasSeenFirstRunGuide.withLock { $0 = true }
                $isSingleCanvasEnabled.withLock { $0 = false }
            }

            #expect(defaults.object(forKey: "hasSeenFirstRunGuide") as? Bool == true)
            #expect(defaults.object(forKey: "singleCanvasEnabled") as? Bool == false)
            #expect(defaults.object(forKey: "singleCanvasEnabled") != nil)
            #expect(!defaults.bool(forKey: "singleCanvasEnabled"))
        }
    }

    /// 앱 타깃 `LaunchProgressFeature` · `AppCoordinatorFeature` 와 같은 선언을 쓴다 — develop 에는 앱 단위 시험 타깃이 없다.
    @Test("시작 화면의 마지막 버전은 String, 초기 복원 결과는 JSON 으로 저장한다")
    func launchKeysStoreVersionAsStringAndOutcomeAsJSON() throws {
        try withSuite { defaults in
            withDependencies { $0.defaultAppStorage = defaults } operation: {
                @Shared(.appStorage("lastSeenAppVersion")) var lastSeenAppVersion: String?
                @Shared(.codableAppStorage("initialRestoreOutcome")) var initialRestoreOutcome: InitialRestoreOutcome?
                $lastSeenAppVersion.withLock { $0 = "2.0.0" }
                $initialRestoreOutcome.withLock { $0 = .startedFirst }
            }

            #expect(defaults.object(forKey: "lastSeenAppVersion") as? String == "2.0.0")
            let outcome = try #require(defaults.data(forKey: "initialRestoreOutcome"))
            #expect(try JSONDecoder().decode(InitialRestoreOutcome?.self, from: outcome) == .startedFirst)
        }
    }

    /// 시험마다 새 UserDefaults 저장소를 만들고 끝나면 지운다.
    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "AppStorageFormatTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
