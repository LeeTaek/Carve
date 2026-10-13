//
//  AppLanguage.swift
//  ClientInterfaces
//
//  Created by Claude on 10/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

/// 앱 화면 언어 — 카탈로그가 옮겨 둔 언어(한국어 원문 · 영어)(영어 현지화 결정 5 · 20).
public enum AppLanguage: String, CaseIterable, Hashable, Sendable {
    case korean = "ko"
    case english = "en"

    /// 역할: 번들이 고른 현지화 목록에서 앱 화면 언어를 고른다.
    /// 입력 · 출력: 현지화 목록(예: 모듈 번들의 `preferredLocalizations` — iOS 앱별 언어 · 기기 언어를 따른다) → 첫 항목의 언어.
    ///   모르는 언어 · 빈 목록이면 원문 언어(한국어).
    /// 부작용: 없음.
    public static func current(preferredLocalizations: [String]) -> Self {
        guard let first = preferredLocalizations.first else { return .korean }
        let languageCode = Locale.Language(identifier: first).languageCode?.identifier
        return allCases.first { $0.rawValue == languageCode } ?? .korean
    }

    /// 역할: iOS 선호 언어 목록에서 앱이 지원하는 언어를 고른다 — 앞에서부터 처음 맞는 언어(지역은 보지 않는다)로, iOS 가 번들 현지화를 고르는 규칙과 같다.
    /// 입력 · 출력: 선호 언어(`Locale.preferredLanguages`) → 앱 언어. 맞는 언어가 없으면 원문 언어(한국어 — 개발 지역 ko).
    /// 부작용: 없음.
    public static func resolve(preferredLanguages: [String]) -> Self {
        for identifier in preferredLanguages {
            let languageCode = Locale.Language(identifier: identifier).languageCode?.identifier
            if let language = allCases.first(where: { $0.rawValue == languageCode }) {
                return language
            }
        }
        return .korean
    }

    /// 그 언어로 적은 이름. 언어 목록의 관례대로 화면 언어와 상관없이 「한국어」 · 「English」 로 적는다 — 카탈로그를 지나지 않는다.
    public var nativeName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        }
    }

    /// 역할: 이 언어로 문구를 찾는 locale 을 만든다 — 지역 · 달력 · 시간제 · 주 시작일은 기준 로케일 것을 둔다.
    /// 입력 · 출력: 기준 로케일 → 언어만 바꾼 locale(예: `ko_KR@hours=h23` → `en_KR@hours=h23`).
    /// 부작용: 없음.
    ///
    /// ⚠️ `languageComponents` 를 통째로 새로 넣으면 지역이 사라진다 — `ko_KR` 의 지역은 `languageComponents.region` 에 들어 있다
    ///    (2026-10-13 iPadOS 17.5 · 26.2: `ko_KR` → `en`). 언어 코드만 바꾸고, 원래 언어의 문자 체계(script)만 비운다.
    public func locale(base: Locale = .autoupdatingCurrent) -> Locale {
        var components = Locale.Components(locale: base)
        components.languageComponents.languageCode = Locale.LanguageCode(rawValue)
        components.languageComponents.script = nil
        return Locale(components: components)
    }

    /// 역할: 지금 화면 언어의 locale 을 얻는다 — 리듀서 · effect · 인프라가 문구(알림 · 안내 · 저장되는 표시 문자열)를 만들 때 한 번 얻어 쓴다.
    ///   뷰는 이 함수를 부르지 않고 환경 `locale` 을 쓴다 — 앱 루트(`AppCoordinatorView`)가 같은 규칙으로 넣고, 바뀌면 SwiftUI 가 다시 그린다.
    ///   얻은 locale 로 만든 문구는 상태에 그 언어로 남는다 — 언어를 바꿔도 다시 만들 때까지 그대로다(떠 있는 알림과 같다).
    /// 입력 · 출력: 없음(이 실행에서 앱 안에서 고른 언어 `appLanguageOverride` 와 iOS 선호 언어를 읽는다) → `displayLocale(override:preferredLanguages:base:)`.
    /// 부작용: 없음 — 읽기만 한다. 고른 언어는 `defaultInMemoryStorage` 의존성의 저장소에서 읽으므로, 시험은 `withDependencies` 로 저장소를 넣는다.
    public static func displayLocale() -> Locale {
        @SharedReader(.appLanguageOverride) var languageOverride: AppLanguage?
        return displayLocale(override: languageOverride, preferredLanguages: Locale.preferredLanguages)
    }

    /// 역할: 화면 언어의 locale 을 정하는 규칙 — 고른 언어가 있으면 그 언어, 없으면 iOS 선호 언어에서 앱이 옮긴 첫 언어(`resolve` — 번들이 현지화를 고르는 규칙과 같다).
    /// 입력 · 출력: 고른 언어(없으면 nil) · iOS 선호 언어 · 기준 로케일 → 그 언어로 바꾼 locale(지역 · 달력 · 시간제는 기준 로케일 것 — `locale(base:)`).
    /// 부작용: 없음.
    ///
    /// ⚠️ 고른 언어가 없을 때 `Locale.autoupdatingCurrent` 를 그대로 쓰지 않는다. 선호 언어에 앱이 옮긴 언어가 없으면(예: 일본어 하나) 번들은 개발 언어 ko 를
    ///    고르는데 `Locale.current` 의 언어는 en 이다(2026-10-13 iPadOS 26.2 — 번들 `[ko]` · `Locale.current` `en_JP`). 그 locale 로 풀면 카탈로그 문구는 영어,
    ///    키 기반 `Text("…", bundle:)` 는 한국어로 한 화면에 섞인다. 언어를 적은 locale 이면 둘 다 같은 언어다.
    public static func displayLocale(override: AppLanguage?, preferredLanguages: [String], base: Locale = .autoupdatingCurrent) -> Locale {
        (override ?? resolve(preferredLanguages: preferredLanguages)).locale(base: base)
    }
}

/// 앱 언어 고르기 — 시스템 설정 따름 · 한국어 · English.
///
/// 저장은 iOS 앱별 언어와 **같은 값**(앱 UserDefaults 도메인의 `AppleLanguages`)이다 — 설정 앱 › 새기다 › 언어와 같은 값을 읽고 쓴다
/// (단일 진실, 2026-10-13 결정. 17.5 · 18.6 · 26.2 · 27.0 에서 앱이 쓴 값과 설정 앱 표시가 같았다).
/// 「시스템 설정」은 키가 없는 상태다 — 설정 앱에서 「기본 설정」 언어를 골라도 iOS 가 키를 지운다.
public enum AppLanguageSelection: String, CaseIterable, Hashable, Sendable {
    case system
    case korean
    case english

    /// 고른 언어. 시스템 설정이면 nil.
    public var language: AppLanguage? {
        switch self {
        case .system: nil
        case .korean: .korean
        case .english: .english
        }
    }

    /// 역할: 저장값에서 고른 것을 읽는다.
    /// 입력 · 출력: 앱 도메인의 `AppleLanguages`(키가 없으면 nil) → 첫 항목의 언어. 키가 없거나 지원하지 않는 언어면 시스템 설정.
    /// 부작용: 없음.
    public init(appleLanguages: [String]?) {
        guard let first = appleLanguages?.first else {
            self = .system
            return
        }
        switch Locale.Language(identifier: first).languageCode?.identifier {
        case AppLanguage.korean.rawValue: self = .korean
        case AppLanguage.english.rawValue: self = .english
        default: self = .system
        }
    }

    /// 역할: 저장할 값을 만든다 — 설정 앱과 같은 모양 `[고른 언어-지역, 나머지 선호 언어…]`.
    /// 입력 · 출력: 지금 선호 언어 · 지역 코드 → 저장할 배열. 시스템 설정이면 nil(키를 지운다).
    /// 부작용: 없음.
    public func appleLanguages(preferredLanguages: [String], region: String?) -> [String]? {
        guard let language else { return nil }
        let code = language.rawValue
        let chosen = region.map { "\(code)-\($0)" } ?? code
        let others = preferredLanguages.filter { Locale.Language(identifier: $0).languageCode?.identifier != code }
        return [chosen] + others
    }
}

/// 앱 언어 저장 — iOS 앱별 언어(앱 도메인 `AppleLanguages`)를 읽고 쓴다. 구현은 App 타깃.
///
/// 저장한 언어는 **다음 실행부터** iOS 가 앱 전체(번들 · `Locale.current` · 시스템이 그리는 일부 화면)에 쓴다.
/// 지금 실행의 화면은 `appLanguageOverride` 로 바꾼다 — 설정 앱에서 바꿀 때와 달리 iOS 가 앱을 종료하지 않는다.
public protocol AppLanguageClient: Sendable {
    /// 저장된 고르기. 키가 없으면 시스템 설정.
    func selection() -> AppLanguageSelection
    /// 고른 것을 저장한다. 시스템 설정은 키를 지운다.
    func save(_ selection: AppLanguageSelection)
    /// 지금 iOS 선호 언어로 고른 앱 언어 — 저장 바로 뒤에 부르면 고른 언어(시스템 설정이면 기기 언어)다.
    func resolvedLanguage() -> AppLanguage
}

private enum AppLanguageClientKey: DependencyKey {
    static let liveValue: any AppLanguageClient = UnimplementedAppLanguageClient()
    static let testValue: any AppLanguageClient = UnimplementedAppLanguageClient()
}

public extension DependencyValues {
    /// 앱 언어 저장.
    var appLanguageClient: any AppLanguageClient {
        get { self[AppLanguageClientKey.self] }
        set { self[AppLanguageClientKey.self] = newValue }
    }
}

/// 주입하지 않았을 때 — 저장한 척하지 않고 문제로 알린다.
private struct UnimplementedAppLanguageClient: AppLanguageClient {
    func selection() -> AppLanguageSelection {
        reportIssue("AppLanguageClient 를 주입하지 않았다 — selection()")
        return .system
    }

    func save(_ selection: AppLanguageSelection) {
        reportIssue("AppLanguageClient 를 주입하지 않았다 — save(_:)")
    }

    func resolvedLanguage() -> AppLanguage {
        reportIssue("AppLanguageClient 를 주입하지 않았다 — resolvedLanguage()")
        return .korean
    }
}

public extension SharedReaderKey where Self == InMemoryKey<AppLanguage?>.Default {
    /// 이 실행에서 앱 안 고르기로 바꾼 화면 언어. nil 이면 iOS 선호 언어에서 앱이 옮긴 첫 언어(번들이 고른 언어와 같다)다.
    ///
    /// 설정 › 화면 › 언어가 쓰고, 앱 루트(`AppCoordinatorView`)가 읽어 환경 `locale` 을 바꾼다. 리듀서 · effect · 인프라는 이 값을 직접 읽지 않고
    /// `AppLanguage.displayLocale()` 로 같은 규칙의 locale 을 얻는다. 키 기반 `Text("…", bundle:)` 은 환경을 따라 바로 바뀌고,
    /// 미리 만든 문자열(카탈로그 도우미 · 표시용 함수)은 넘긴 locale 의 언어로 만든다 — 보관함 plan 「Carve 앱 언어 즉시 전환」 단계 2 · 3.
    static var appLanguageOverride: Self {
        Self[.inMemory("appLanguageOverride"), default: nil]
    }
}
