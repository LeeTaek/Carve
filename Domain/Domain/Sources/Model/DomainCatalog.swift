//
//  DomainCatalog.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//

import Foundation

/// Domain 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문) 문구를 꺼낸다(영어 현지화 결정 5).
///
/// - 권 이름 · 참조 형식 · 번역본 이름 · 글꼴 이름 · 의견 종류 · 백업 파일 이름이 이 도우미로 문구를 꺼낸다.
/// - 다른 모듈 도우미(`CarveFeatureCatalog` · `ChartCatalog` · `SettingsCatalog` · `UIComponentsCatalog` · `AppCatalog`)와 같은 모양이다 — 늘 locale 을 받는다(즉시 전환 단계 3).
///   이 모듈에서 `String(localized:)` 를 직접 부르는 곳은 이 파일뿐이다(lint `localized_string_outside_catalog`).
enum DomainCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일(뷰는 환경 locale, 뷰 밖은 `AppLanguage.displayLocale()`) → 그 언어로 현지화된 문자열.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다.
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
