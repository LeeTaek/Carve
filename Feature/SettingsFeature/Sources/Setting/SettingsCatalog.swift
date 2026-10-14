//
//  SettingsCatalog.swift
//  SettingsFeature
//
//  설정 화면 문구를 모듈 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문)에서 꺼낸다(영어 현지화 결정 5 · 6 · 8).
//  SwiftUI 리터럴은 `Text("…", bundle: .module)` 로 바로 쓰고, `String` 으로 흐르는 문구(Copy enum · Popup · Action 페이로드 ·
//  컴포넌트 파라미터)는 여기를 지난다. 언어는 늘 부르는 쪽이 넘긴다 — 뷰는 환경 `locale`, 리듀서 · effect 는 `AppLanguage.displayLocale()`
//  (즉시 전환 단계 3). 날짜 · 용량 서식도 넘겨받은 그 locale 로 적는다.
//

import Foundation

enum SettingsCatalog {
    /// 역할: 카탈로그 문구를 주어진 언어로 꺼낸다 — 뷰는 환경 `locale` 을, 리듀서 · effect 는 `AppLanguage.displayLocale()` 을 넘긴다.
    ///   앱 안에서 언어를 고르면 다시 시작하지 않고 바뀐다(즉시 전환 단계 2 · 3).
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함) · 로케일 → 그 언어로 현지화된 문자열. 수는 카탈로그의 복수형 변형을 따르고,
    ///   보간 값의 서식도 이 로케일을 따른다.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다(영어 현지화 결정 6).
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
