//
//  AppStorageFormatMigrationTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 10/1/26.
//

@testable import CarveFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 2.0.0(Xcode 27 빌드)이 JSON Data 로 쓴 기본 타입 설정을 앱 시작 때 기본 타입으로 되돌린다(`AppStorageFormatMigration`).
/// JSON 값은 그 빌드의 `CodableAppStorageKey` 처럼 `JSONEncoder` 로 만든다.
@MainActor
struct AppStorageFormatMigrationTesting {
    @Test("2.0.0 이 JSON 으로 쓴 Bool · Int · String 값을 기본 타입으로 되돌린다")
    func restoresJSONEncodedPrimitives() throws {
        try withSuite { defaults in
            let encoder = JSONEncoder()
            defaults.set(try encoder.encode(true), forKey: "isLeftHanded")
            defaults.set(try encoder.encode(false), forKey: "allowFingerDrawing")
            defaults.set(try encoder.encode(true), forKey: "hasSeenFirstRunGuide")
            defaults.set(try encoder.encode(false), forKey: SingleCanvasFlag.appStorageKey)
            defaults.set(try encoder.encode(2), forKey: "selectedColorIndex")
            defaults.set(try encoder.encode(1), forKey: "selectedWidthIndex")
            defaults.set(try encoder.encode("2.0.0"), forKey: "lastSeenAppVersion")

            let restored = AppStorageFormatMigration.restorePrimitiveValues(in: defaults)

            let migrated = AppStorageFormatMigration.boolKeys + AppStorageFormatMigration.intKeys + AppStorageFormatMigration.optionalStringKeys
            #expect(Set(restored) == Set(migrated))
            #expect(defaults.object(forKey: "isLeftHanded") as? Bool == true)
            #expect(defaults.object(forKey: "allowFingerDrawing") as? Bool == false)
            #expect(defaults.object(forKey: "hasSeenFirstRunGuide") as? Bool == true)
            #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) as? Bool == false)
            #expect(defaults.object(forKey: "selectedColorIndex") as? Int == 2)
            #expect(defaults.object(forKey: "selectedWidthIndex") as? Int == 1)
            #expect(defaults.object(forKey: "lastSeenAppVersion") as? String == "2.0.0")
        }
    }

    @Test("JSON null 로 남은 마지막 버전은 지운다 — 값이 없는 설치와 같다")
    func removesJSONNullOptionalString() throws {
        try withSuite { defaults in
            defaults.set(try JSONEncoder().encode(String?.none), forKey: "lastSeenAppVersion")

            let restored = AppStorageFormatMigration.restorePrimitiveValues(in: defaults)

            #expect(restored == ["lastSeenAppVersion"])
            #expect(defaults.object(forKey: "lastSeenAppVersion") == nil)
        }
    }

    @Test("기본 타입 값과 없는 값은 건드리지 않고, 여러 번 불러도 결과가 같다")
    func leavesPlainValuesAndIsIdempotent() throws {
        try withSuite { defaults in
            defaults.set(true, forKey: "isLeftHanded")
            defaults.set(2, forKey: "selectedColorIndex")
            defaults.set("2.0.0", forKey: "lastSeenAppVersion")

            #expect(AppStorageFormatMigration.restorePrimitiveValues(in: defaults).isEmpty)
            #expect(AppStorageFormatMigration.restorePrimitiveValues(in: defaults).isEmpty)
            #expect(defaults.object(forKey: "isLeftHanded") as? Bool == true)
            #expect(defaults.object(forKey: "selectedColorIndex") as? Int == 2)
            #expect(defaults.object(forKey: "lastSeenAppVersion") as? String == "2.0.0")
            #expect(defaults.object(forKey: "allowFingerDrawing") == nil)
        }
    }

    @Test("풀리지 않는 Data 와 이전 대상이 아닌 키는 그대로 둔다")
    func leavesUndecodableAndUnrelatedDataUntouched() throws {
        try withSuite { defaults in
            let broken = Data("not json".utf8)
            let title = try JSONEncoder().encode(BibleChapter.initialState)
            defaults.set(broken, forKey: "isLeftHanded")
            defaults.set(title, forKey: "title")

            #expect(AppStorageFormatMigration.restorePrimitiveValues(in: defaults).isEmpty)
            #expect(defaults.data(forKey: "isLeftHanded") == broken)
            #expect(defaults.data(forKey: "title") == title)
        }
    }

    @Test("되돌린 값을 화면 State 가 그대로 읽는다")
    func restoredValuesLoadIntoFeatureState() throws {
        try withSuite { defaults in
            let encoder = JSONEncoder()
            defaults.set(try encoder.encode(true), forKey: "isLeftHanded")
            defaults.set(try encoder.encode(2), forKey: "selectedColorIndex")

            AppStorageFormatMigration.restorePrimitiveValues(in: defaults)
            let settings = withDependencies { $0.defaultAppStorage = defaults } operation: { SentenceSettingsFeature.State() }
            let palette = withDependencies { $0.defaultAppStorage = defaults } operation: { PencilPalatteFeature.State() }

            #expect(settings.isLeftHanded)
            #expect(palette.selectedColorIndex == 2)
        }
    }

    /// 앱 타깃 `LaunchProgressFeature` 와 같은 선언으로 읽는다 — 시작 화면이 앞서 들어간 설치로 판단하는 값이다.
    @Test("JSON 으로 남은 마지막 버전을 되돌리면 시작 화면 선언이 String 으로 읽는다")
    func restoredVersionLoadsThroughLaunchDeclaration() throws {
        try withSuite { defaults in
            defaults.set(try JSONEncoder().encode("2.0.0"), forKey: "lastSeenAppVersion")

            AppStorageFormatMigration.restorePrimitiveValues(in: defaults)
            let version = withDependencies { $0.defaultAppStorage = defaults } operation: { () -> String? in
                @Shared(.appStorage("lastSeenAppVersion")) var lastSeenAppVersion: String?
                return lastSeenAppVersion
            }

            #expect(version == "2.0.0")
        }
    }

    /// 시험마다 새 UserDefaults 저장소를 만들고 끝나면 지운다.
    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "AppStorageFormatMigrationTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
