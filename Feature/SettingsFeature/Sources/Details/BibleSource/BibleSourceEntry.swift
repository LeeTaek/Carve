//
//  BibleSourceEntry.swift
//  SettingsFeature
//
//  「성경 본문 출처」 의 번역본 한 항목 — 이름 · 판 · 권리 · 출처(영어 현지화 결정 11).
//  본문 사본의 출처 기록은 DAG 캐시 `bibletext/PROVENANCE.md`(KJV 커밋 · BSB zip 받은 날 · 체크섬)에 있다.
//

import Domain
import Foundation

/// 「성경 본문 출처」 의 한 항목 — 번역본 하나의 이름 · 판 · 권리 · 출처.
///
/// 항목은 번역본만 갖고, 화면에 적는 문구는 그때 앱 언어로 꺼낸다(`locale` 을 주면 그 언어). 주소는 번역하지 않는다.
public struct BibleSourceEntry: Equatable, Hashable, Sendable, Identifiable {
    /// 이 항목의 번역본.
    public let translation: Translation

    /// 항목 식별 — 번역본마다 하나다.
    public var id: Translation { translation }

    /// - Parameter translation: 이 항목의 번역본.
    public init(translation: Translation) {
        self.translation = translation
    }

    /// 화면에 적는 항목 — `Translation.allCases` 순서(개역개정 · KJV · BSB).
    public static var all: [Self] {
        Translation.allCases.map(Self.init(translation:))
    }

    /// 번역본 전체 이름(ko 「개역개정」 · en 「New Korean Revised Version」, 「King James Version」, 「Berean Standard Bible」).
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
    public func name(locale: Locale? = nil) -> String {
        translation.fullName(locale: locale)
    }

    /// 번역본 약칭(「KJV」 · 「BSB」, en 「NKRV」). 전체 이름과 같으면(한국어의 개역개정) nil 이다.
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
    public func abbreviation(locale: Locale? = nil) -> String? {
        let short = translation.displayName(locale: locale)
        return short == name(locale: locale) ? nil : short
    }

    /// 본문의 판. 적을 것이 없으면 nil 이다.
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
    public func edition(locale: Locale? = nil) -> String? {
        switch translation {
        case .NKRV, .BSB:
            return nil
        case .KJV:
            return BibleSourceCopy.string("1769년 표준판 본문", locale: locale)
        }
    }

    /// 본문을 쓸 수 있는 권리. 적을 것이 없으면 nil 이다.
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다. 날짜도 이 로케일의 서식으로 적는다.
    public func rights(locale: Locale? = nil) -> String? {
        switch translation {
        case .NKRV:
            // TODO: 허락 근거 확인 뒤 채운다 — 결정 11
            return nil
        case .KJV:
            return BibleSourceCopy.string("영국 밖에서는 공개 도메인", locale: locale)
        case .BSB:
            let dedicated = Self.bsbPublicDomainDate.formatted(Self.dateStyle(locale: locale))
            return BibleSourceCopy.string("CC0 1.0 — \(dedicated) 공개 도메인에 헌정", locale: locale)
        }
    }

    /// 번역본을 낸 곳의 사이트 주소 — 화면에 적는 그대로다(번역하지 않는다). 없으면 nil.
    public var officialSite: String? {
        switch translation {
        case .NKRV, .KJV: nil
        case .BSB: "berean.bible"
        }
    }

    /// 앱에 담은 본문 사본을 받은 곳의 주소 — 화면에 적는 그대로다(번역하지 않는다). 없으면 nil.
    public var textSource: String? {
        switch translation {
        case .NKRV: nil
        case .KJV: "github.com/christislord12/kjv-txt-files"
        case .BSB: "bereanbible.com/bsb_usfm.zip"
        }
    }

    // MARK: - 날짜

    /// BSB 를 CC0 1.0 으로 공개 도메인에 헌정한 날 — 2023-04-30 00:00 UTC.
    static let bsbPublicDomainDate = Date(timeIntervalSince1970: 1_682_812_800)

    /// 역할: 헌정한 날을 적는 서식 — 기기(또는 주어진) 로케일의 긴 날짜(ko 「2023년 4월 30일」 · en 「April 30, 2023」).
    /// 입력 · 출력: 로케일(nil 이면 기기 로케일) → 날짜 서식. 날짜가 시간대에 따라 하루 밀리지 않게 UTC 로 적는다.
    /// 부작용: 없음.
    private static func dateStyle(locale: Locale?) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .long,
            time: .omitted,
            locale: locale ?? .autoupdatingCurrent,
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt
        )
    }
}
