//
//  AppCatalog.swift
//  Carve
//
//  Created by Claude on 10/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 앱 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문 · 앱 번들 `.main`) 문구를 꺼낸다(영어 현지화 결정 5).
///
/// - `String` 으로 흐르는 문구(알림 제목 · 버튼 제목 · 안내 문장)에 쓴다. SwiftUI 리터럴은 `Text("…", bundle: .main)` 로 둔다.
/// - 다른 모듈 도우미(`ChartCatalog` · `CarveFeatureCatalog` · `SettingsCatalog`)와 같은 모양이다 — 늘 locale 을 받는다(즉시 전환 단계 3).
/// - 앱 타깃에만 있다 — 위젯(자기 번들)과 호스트 없는 `CarveAppTest`(앱 소스 일부만 함께 컴파일)에는 들어가지 않는다.
enum AppCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일(뷰는 환경 locale, 뷰 밖은 `AppLanguage.displayLocale()`) → 그 언어로 현지화된 문자열.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .main)
        return String(localized: resource)
    }
}
