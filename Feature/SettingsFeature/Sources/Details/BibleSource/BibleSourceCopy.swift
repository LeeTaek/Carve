//
//  BibleSourceCopy.swift
//  SettingsFeature
//
//  설정 → 앱 버전 → 「성경 본문 출처」 의 문구(영어 현지화 결정 11). 문구는 모듈 카탈로그(`Resources/Localizable.xcstrings`)에 ko · en 으로 둔다.
//  주소 문자열은 번역하지 않는다 — 카탈로그 키에 넣지 않는다. 언어는 부르는 쪽이 넘긴다 — 뷰는 환경 `locale`(즉시 전환 단계 3).
//

import Foundation

enum BibleSourceCopy {
    /// 화면 이름 — 앱 버전 화면의 행 이름이자 화면 제목.
    /// - Parameter locale: 언어를 정할 로케일 — 뷰는 환경 `locale` 을 넘긴다.
    static func title(locale: Locale) -> String {
        string("성경 본문 출처", locale: locale)
    }

    /// 화면 첫 줄 — 무엇을 적은 화면인가.
    static func summary(locale: Locale) -> String { string("번역본마다 본문의 판 · 권리 · 출처를 적었어요.", locale: locale) }

    // MARK: - 항목 이름

    /// 본문의 판(예: 1769년 표준판).
    static func editionLabel(locale: Locale) -> String { string("판", locale: locale) }
    /// 본문을 쓸 수 있는 권리.
    static func rightsLabel(locale: Locale) -> String { string("권리", locale: locale) }
    /// 번역본을 낸 곳의 사이트.
    static func officialSiteLabel(locale: Locale) -> String { string("공식 사이트", locale: locale) }
    /// 앱에 담은 본문 사본을 받은 곳.
    static func textSourceLabel(locale: Locale) -> String { string("본문 사본 출처", locale: locale) }

    /// 역할: 카탈로그 문구를 주어진 언어로 꺼낸다 — 모듈 도우미 `SettingsCatalog.string(_:locale:)` 와 같은 길(같은 카탈로그)이다.
    /// 입력 · 출력: 문구(키 = 한국어 원문, 보간 값 포함)와 로케일 → 그 언어로 현지화된 문자열.
    /// 부작용: 없음.
    static func string(_ value: String.LocalizationValue, locale: Locale) -> String {
        SettingsCatalog.string(value, locale: locale)
    }
}
