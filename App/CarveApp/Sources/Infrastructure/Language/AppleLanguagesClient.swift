//
//  AppleLanguagesClient.swift
//  Carve
//
//  Created by Claude on 10/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import Foundation
import WidgetKit

/// 앱 언어 저장의 실제 구현 — 앱 도메인의 `AppleLanguages` 를 읽고 쓴다(설정 앱 › 새기다 › 언어와 같은 값).
///
/// 저장 모양 · 시스템 설정(키 삭제) 규칙은 `AppLanguageSelection` 이 갖는다. 여기서는 UserDefaults 와 iOS 선호 언어만 다룬다.
/// 저장한 뒤의 화면 언어는 위젯에도 알린다(`WidgetAppLanguage`).
struct AppleLanguagesClient: AppLanguageClient {
    private static let key = "AppleLanguages"

    func selection() -> AppLanguageSelection {
        AppLanguageSelection(appleLanguages: storedValue())
    }

    func save(_ selection: AppLanguageSelection) {
        // 위젯도 같은 화면 언어를 따르게 — `AppleLanguages` 를 쓰거나 지운 뒤의 언어(시스템 설정이면 기기 언어)를 App Group 에 적는다.
        defer { WidgetAppLanguage.publish(resolvedLanguage()) }
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

/// 위젯이 앱 화면 언어를 따르게 App Group 에 적는다(`VerseWidgetSharing.appLanguageKey`) — 위젯은 그 값으로 표시 locale 을 만든다.
///
/// 위젯 확장은 시스템이 실행 인자로 넘기는 앱별 언어(`-AppleLanguages`)로 뜨는데, 그 값은 설정 앱에서 바꿀 때와 재부팅 때만 바뀐다 —
/// 앱이 `AppleLanguages` 를 직접 써도 새로 뜬 위젯 확장은 옛 언어다(2026-10-13 iPadOS 26.2 시뮬레이터). 그래서 App Group 값이 늘 이기고,
/// 앱 안에서 고를 때(`AppleLanguagesClient.save`)와 앱이 시작할 때 적는다. 설정 앱에서 바꾸면 위젯은 앱을 다시 열 때까지 App Group 의 옛 언어다.
enum WidgetAppLanguage {
    /// 역할: 화면 언어를 App Group 에 적고, 적힌 값이 바뀌었으면 위젯을 다시 그리게 한다.
    /// 입력 · 출력: 화면 언어 → 없음.
    /// 부작용: App Group UserDefaults 쓰기 · 위젯 타임라인 다시 읽기 요청(값이 바뀐 때만 — 시작할 때마다 깨우지 않는다).
    static func publish(_ language: AppLanguage) {
        guard let defaults = UserDefaults(suiteName: VerseWidgetSharing.appGroupID),
              defaults.string(forKey: VerseWidgetSharing.appLanguageKey) != language.rawValue else { return }
        defaults.set(language.rawValue, forKey: VerseWidgetSharing.appLanguageKey)
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: VerseWidgetSharing.widgetKind)
        }
    }

    /// 역할: 앱이 시작할 때 이 실행의 화면 언어로 맞춘다 — 설정 앱에서 앱 언어를 바꾸면 iOS 가 앱을 종료하므로 다음 시작이 맞춘다.
    /// 입력 · 출력: 없음(번들이 고른 현지화 — iOS 앱별 언어 · 기기 언어를 따른다) → 없음.
    /// 부작용: `publish(_:)` 와 같다.
    static func publishLaunchLanguage() {
        publish(.current(preferredLocalizations: Bundle.main.preferredLocalizations))
    }
}
