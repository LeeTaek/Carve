//
//  AppleLanguagesClient.swift
//  Carve
//
//  Created by Claude on 10/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import Foundation

/// 앱 언어 저장의 실제 구현 — 앱 도메인의 `AppleLanguages` 를 읽고 쓴다(설정 앱 › 새기다 › 언어와 같은 값).
///
/// 저장 모양 · 시스템 설정(키 삭제) 규칙은 `AppLanguageSelection` 이 갖는다. 여기서는 UserDefaults 와 iOS 선호 언어만 다룬다.
struct AppleLanguagesClient: AppLanguageClient {
    private static let key = "AppleLanguages"

    func selection() -> AppLanguageSelection {
        AppLanguageSelection(appleLanguages: storedValue())
    }

    func save(_ selection: AppLanguageSelection) {
        let defaults = UserDefaults.standard
        guard let value = selection.appleLanguages(
            preferredLanguages: Locale.preferredLanguages,
            region: Locale.current.region?.identifier
        ) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(value, forKey: Self.key)
    }

    func resolvedLanguage() -> AppLanguage {
        // 같은 프로세스에서도 저장 직후 `Locale.preferredLanguages` 는 바로 바뀐다(번들 · `Locale.current` 는 다음 실행부터 — 2026-10-13 관문 S).
        AppLanguage.resolve(preferredLanguages: Locale.preferredLanguages)
    }

    /// 앱 도메인에 저장된 값만 읽는다 — `UserDefaults.standard` 로 읽으면 기기 · 실행 인자 도메인이 섞여 「시스템 설정」을 가릴 수 없다.
    private func storedValue() -> [String]? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: bundleID)?[Self.key] as? [String]
    }
}
