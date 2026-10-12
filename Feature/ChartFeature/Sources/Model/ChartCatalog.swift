//
//  ChartCatalog.swift
//  ChartFeature
//
//  Created by Claude on 10/12/26.
//

import Foundation

/// ChartFeature 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문) 문구를 꺼낸다(영어 현지화 결정 5 · 6).
enum ChartCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일 → 현지화된 문자열.
    ///   로케일이 nil 이면 앱(기기) 언어 — 번들이 고른 언어(`String(localized:bundle:)`)다.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale?) -> String {
        guard let locale else { return String(localized: value, bundle: .module) }
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방식).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
