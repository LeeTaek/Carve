//
//  AppStorageFormatMigration.swift
//  CarveFeature
//
//  Created by Claude on 10/1/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Foundation

/// 2.0.0(Xcode 27 빌드)이 JSON Data 로 저장한 기본 타입 설정을 Sharing 의 기본 타입 형식으로 되돌린다.
///
/// 그 빌드는 `.appStorage("키")` 가 Bool · Int · `String?` 값에서도 `CodableAppStorageKey` 로 컴파일돼(`CodableAppStorageKey.swift` 참고)
/// 이 키들을 JSON(`true` · `2` · `"2.0.1"` · `null`)으로 썼다. 고친 빌드는 Sharing 의 `AppStorageKey` 로 기본 타입을 읽으므로,
/// 설정을 읽는 Store 를 만들기 전에 앱 시작 때 부른다. 이미 기본 타입으로 저장된 값(1.x · Xcode 26.x 빌드)은 건드리지 않는다.
/// 2.0.0 이 처음 읽으며 기본값으로 덮어쓴 1.x 값은 되살릴 수 없다 — 이 이전은 그 뒤에 사용자가 바꾼 값을 지킨다.
public enum AppStorageFormatMigration {
    /// 2.0.0 이 JSON 으로 쓴 Bool 키.
    static let boolKeys = ["isLeftHanded", "allowFingerDrawing", "hasSeenFirstRunGuide", SingleCanvasFlag.appStorageKey]
    /// 2.0.0 이 JSON 으로 쓴 Int 키.
    static let intKeys = ["selectedColorIndex", "selectedWidthIndex"]
    /// 2.0.0 이 JSON 으로 쓴 `String?` 키. JSON `null` 은 값이 없다는 뜻이라 지운다.
    static let optionalStringKeys = ["lastSeenAppVersion"]

    /// JSON Data 로 남은 값을 기본 타입으로 바꾼다. 여러 번 불러도 결과가 같다.
    ///
    /// - Parameter defaults: `@Shared(.appStorage)` 가 쓰는 저장소. 앱은 `.standard` 를 넘긴다.
    /// - Returns: 형식을 바꾼 키(시험 · 로그용). 부작용: 그 키들을 `defaults` 에 다시 쓰거나 지운다.
    @discardableResult
    public static func restorePrimitiveValues(in defaults: UserDefaults) -> [String] {
        var restored: [String] = []
        for key in boolKeys {
            guard let value = decodedValue(Bool.self, forKey: key, in: defaults) else { continue }
            defaults.set(value, forKey: key)
            restored.append(key)
        }
        for key in intKeys {
            guard let value = decodedValue(Int.self, forKey: key, in: defaults) else { continue }
            defaults.set(value, forKey: key)
            restored.append(key)
        }
        for key in optionalStringKeys {
            guard let value = decodedValue(String?.self, forKey: key, in: defaults) else { continue }
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            restored.append(key)
        }
        if !restored.isEmpty {
            Log.info("appStorage 형식 되돌림", restored)
        }
        return restored
    }

    /// 키의 값이 JSON Data 이고 그 타입으로 풀리면 그 값. 기본 타입 값 · 값 없음 · 풀리지 않는 Data 는 nil 이고 그대로 둔다.
    private static func decodedValue<Value: Decodable>(_ type: Value.Type, forKey key: String, in defaults: UserDefaults) -> Value? {
        guard let data = defaults.object(forKey: key) as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
