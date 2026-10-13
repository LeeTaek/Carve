//
//  ChartCatalog.swift
//  ChartFeature
//
//  Created by Claude on 10/12/26.
//

import Foundation

/// ChartFeature 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문) 문구를 꺼낸다(영어 현지화 결정 5 · 6).
///
/// - `String` 으로 흐르는 문구(컴포넌트 인자 · 접근성 문장)에 쓴다. SwiftUI 리터럴은 `Text("…", bundle: .module)` 로 둔다.
/// - 뷰는 환경 `locale` 을 넘긴다 — 앱 안에서 언어를 고르면 다시 시작하지 않고 바뀐다(즉시 전환 단계 3, 룰북 현지화 9).
enum ChartCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일(뷰는 환경 locale) → 그 언어로 현지화된 문자열. 수는 카탈로그의 복수형 변형을 따른다.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방식).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
