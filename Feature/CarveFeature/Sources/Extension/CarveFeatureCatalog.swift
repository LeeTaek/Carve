//
//  CarveFeatureCatalog.swift
//  CarveFeature
//
//  Created by Claude on 10/12/26.
//

import Foundation

/// CarveFeature 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문) 문구를 꺼낸다(영어 현지화 결정 5).
///
/// - `String` 으로 흐르는 문구(컴포넌트 인자 · 안내 · 확인창)에 쓴다. SwiftUI 리터럴은 `Text("…", bundle: .module)` 로 둔다.
/// - 늘 로케일을 받는다(즉시 전환 단계 3) — 뷰는 환경 `locale`, 리듀서 · effect 는 `AppLanguage.displayLocale()`, 시험은 `Locale(identifier: "en")` 등을 넘긴다.
///   이 모듈에서 `String(localized:)` 를 직접 부르는 곳은 이 파일뿐이다.
enum CarveFeatureCatalog {
    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일 → 그 로케일 언어로 현지화된 문자열.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
