//
//  SettingsCatalog.swift
//  SettingsFeature
//
//  설정 화면 문구를 모듈 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko · 키는 한국어 원문)에서 꺼낸다(영어 현지화 결정 5 · 6 · 8).
//  SwiftUI 리터럴은 `Text("…", bundle: .module)` 로 바로 쓰고, `String` 으로 흐르는 문구(Copy enum · Popup · Action 페이로드 ·
//  컴포넌트 파라미터)는 여기를 지난다.
//

import Foundation

enum SettingsCatalog {
    /// 언어를 고정할 로케일. nil(기본)이면 앱(기기) 언어다.
    ///
    /// 제품 코드는 값을 넣지 않는다 — 시험이 `$locale.withValue(Locale(identifier: "en")) { … }` 로 영어 문구를 확인할 때만 쓴다.
    /// `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다(영어 현지화 결정 6).
    @TaskLocal static var locale: Locale?

    /// 날짜 · 용량 서식의 로케일 — 고정한 언어가 있으면 그것, 없으면 기기 로케일.
    static var formatLocale: Locale { locale ?? .autoupdatingCurrent }

    /// 역할: 카탈로그 문구를 지금 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함) → 현지화된 문자열. 수는 카탈로그의 복수형 변형을 따른다.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue) -> String {
        guard let locale else { return String(localized: value, bundle: .module) }
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` · `BibleSourceCopy` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
