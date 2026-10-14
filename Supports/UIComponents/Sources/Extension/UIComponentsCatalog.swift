//
//  UIComponentsCatalog.swift
//  UIComponents
//
//  Created by Claude on 10/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// UIComponents 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문) 문구를 꺼낸다(영어 현지화 결정 5).
///
/// - 공용 컴포넌트가 스스로 적는 문구 중 `String` 으로 흘러야 하는 것(UIKit 라벨 · 공개 기본값)에 쓴다. SwiftUI 리터럴은 `Text("…", bundle: .module)` 로 둔다.
/// - 다른 모듈 도우미(`ChartCatalog` · `CarveFeatureCatalog` · `SettingsCatalog`)와 같은 모양이다 — 늘 locale 을 받는다(즉시 전환 단계 3).
enum UIComponentsCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일(뷰는 환경 locale, 뷰 밖은 `AppLanguage.displayLocale()`) → 그 언어로 현지화된 문자열.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
