//
//  FirstLaunchChapter.swift
//  CarveFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

/// 처음 설치했을 때 여는 장(영어 현지화 결정 4).
///
/// 지금 장(`@Shared(.codableAppStorage("title"))`)의 기본값이다 — 저장값이 있으면 그 값을 그대로 읽으므로 기존 사용자는 개역개정을 유지한다.
/// 기기 선호 언어는 의존성(`\.preferredLanguages`)으로 읽어 시험이 바꿔 넣는다.
extension BibleChapter {
    /// 기기 선호 언어의 첫 언어가 한국어면 개역개정 창세기 1장, 아니면 BSB 창세기 1장(`BibleChapter.initial(preferredLanguages:)`).
    static var firstLaunch: BibleChapter {
        @Dependency(\.preferredLanguages) var preferredLanguages
        return .initial(preferredLanguages: preferredLanguages)
    }
}

extension DependencyValues {
    /// 기기 선호 언어 목록(`Locale.preferredLanguages`). 처음 설치 기본 장(`BibleChapter.firstLaunch`)을 정한다.
    var preferredLanguages: [String] {
        get { self[PreferredLanguagesKey.self] }
        set { self[PreferredLanguagesKey.self] = newValue }
    }
}

private enum PreferredLanguagesKey: DependencyKey {
    static var liveValue: [String] { Locale.preferredLanguages }
    /// 시험은 ko-KR 로 돈다(결정 6) — 기본값이 개역개정이어야 기존 한국어 단언이 그대로다.
    static let testValue: [String] = ["ko-KR"]
}
