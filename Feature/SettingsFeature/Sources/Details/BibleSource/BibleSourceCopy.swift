//
//  BibleSourceCopy.swift
//  SettingsFeature
//
//  설정 → 앱 버전 → 「성경 본문 출처」 의 문구(영어 현지화 결정 11). 문구는 모듈 카탈로그(`Resources/Localizable.xcstrings`)에 ko · en 으로 둔다.
//  주소 문자열은 번역하지 않는다 — 카탈로그 키에 넣지 않는다.
//

import Foundation

enum BibleSourceCopy {
    /// 화면 이름 — 앱 버전 화면의 행 이름이자 화면 제목(앱 언어).
    static var title: String { title(locale: nil) }

    /// 화면 이름을 한 언어로 꺼낸다.
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
    static func title(locale: Locale?) -> String {
        string("성경 본문 출처", locale: locale)
    }

    /// 화면 첫 줄 — 무엇을 적은 화면인가.
    static var summary: String { string("번역본마다 본문의 판 · 권리 · 출처를 적었어요.", locale: nil) }

    // MARK: - 항목 이름

    /// 본문의 판(예: 1769년 표준판).
    static var editionLabel: String { string("판", locale: nil) }
    /// 본문을 쓸 수 있는 권리.
    static var rightsLabel: String { string("권리", locale: nil) }
    /// 번역본을 낸 곳의 사이트.
    static var officialSiteLabel: String { string("공식 사이트", locale: nil) }
    /// 앱에 담은 본문 사본을 받은 곳.
    static var textSourceLabel: String { string("본문 사본 출처", locale: nil) }

    /// 역할: 카탈로그 문구를 한 언어로 꺼낸다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일 → 현지화된 문자열.
    ///   로케일이 nil 이면 앱(기기) 언어 — 번들이 고른 언어(`String(localized:bundle:)`)다.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale?) -> String {
        guard let locale else { return String(localized: value, bundle: .module) }
        // `String(localized:bundle:locale:)` 의 locale 은 보간 값 서식에만 쓰이고 언어를 고르지 않는다.
        // 언어를 고르려면 `LocalizedStringResource` 의 locale 로 푼다(Domain `DomainCatalog` 와 같은 방법).
        let resource = LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL))
        return String(localized: resource)
    }
}
