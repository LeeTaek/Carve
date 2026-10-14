//
//  Translation.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

/// 성경 번역 버전
///
/// - SwiftData 의 `translation` 열에는 `.NKRV` 나 nil 만 쓴다 — 영어 번역본은 행의 `titleName` 접두로 구분한다(`StoredBookKey`).
/// - 지금 번역본은 `@Shared(.appStorage("title"))` 에 저장된 장(`BibleChapter.translation`)이다.
public enum Translation: String, Codable, Sendable, CaseIterable {
    case NKRV       // 개역개정
    case KJV        // King James Version
    case BSB        // Berean Standard Bible

    /// 화면에 적는 번역본 약칭을 한 언어로 꺼낸다. 필사 화면 헤더 부제(`HeaderView`) · 참조 뒤 「 · KJV」 에 쓴다.
    /// 개역개정은 ko 「개역개정」 · en 「NKRV」, KJV · BSB 는 어느 언어든 약칭 그대로다.
    /// - Parameter locale: 언어를 정할 로케일. 뷰는 환경 locale, 리듀서 · 인프라는 `AppLanguage.displayLocale()` 을 넘긴다.
    public func displayName(locale: Locale) -> String {
        switch self {
        case .NKRV: DomainCatalog.string("개역개정", locale: locale)
        case .KJV, .BSB: rawValue
        }
    }

    /// 번역본 전체 이름을 한 언어로 꺼낸다. 번역본 고르기에서 약칭과 함께 보인다.
    /// 개역개정은 ko 「개역개정」 · en 「New Korean Revised Version」, KJV · BSB 는 어느 언어든 영어 이름이다.
    /// - Parameter locale: 언어를 정할 로케일. 뷰는 환경 locale, 리듀서 · 인프라는 `AppLanguage.displayLocale()` 을 넘긴다.
    public func fullName(locale: Locale) -> String {
        switch self {
        // 키 「개역개정」 은 약칭(en 「NKRV」)이 쓴다 — 카탈로그 키는 하나의 영어 값만 가지므로 전체 이름은 「개역개정판」 키에 ko 값 「개역개정」 을 둔다.
        case .NKRV: DomainCatalog.string("개역개정판", locale: locale)
        case .KJV: "King James Version"
        case .BSB: "Berean Standard Bible"
        }
    }

    /// 본문 리소스 파일 이름. 개역개정은 `BibleTitle.rawValue`, 그 밖은 `"<번역본>-<rawValue>"`(예 `KJV-1-01Genesis.txt`)다.
    /// 영어 번역본의 파일 이름은 그 번역본 행의 `titleName`(`StoredBookKey`)과 같은 문자열이다.
    public func resourceFileName(for title: BibleTitle) -> String {
        switch self {
        case .NKRV: title.rawValue
        case .KJV, .BSB: "\(rawValue)-\(title.rawValue)"
        }
    }

    /// 본문 리소스 파일의 문자 인코딩. 개역개정은 CP949(CFStringEncoding `0x0422`), 영어 번역본은 UTF-8 이다.
    public var textEncoding: String.Encoding {
        switch self {
        case .NKRV: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0422))
        case .KJV, .BSB: .utf8
        }
    }

    /// 본문 언어 코드(`"ko"` · `"en"`).
    public var languageCode: String {
        switch self {
        case .NKRV: "ko"
        case .KJV, .BSB: "en"
        }
    }
}
