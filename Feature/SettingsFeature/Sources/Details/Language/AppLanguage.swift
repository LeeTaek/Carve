//
//  AppLanguage.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import UIKit

/// 앱 화면 언어 — 카탈로그가 옮겨 둔 언어(한국어 원문 · 영어)(영어 현지화 결정 5 · 20).
enum AppLanguage: String, CaseIterable, Sendable {
    case korean = "ko"
    case english = "en"

    /// 역할: 지금 앱 화면 언어를 고른다.
    /// 입력 · 출력: 번들이 고른 현지화 목록(기본은 이 모듈 번들 — iOS 앱별 언어 · 기기 언어를 따른다) → 첫 항목의 언어. 모르는 언어면 원문 언어(한국어).
    /// 부작용: 없음.
    static func current(preferredLocalizations: [String] = Bundle.module.preferredLocalizations) -> Self {
        guard let first = preferredLocalizations.first else { return .korean }
        let languageCode = Locale.Language(identifier: first).languageCode?.identifier
        return allCases.first { $0.rawValue == languageCode } ?? .korean
    }

    /// 그 언어로 적은 이름. 언어 목록의 관례대로 화면 언어와 상관없이 「한국어」 · 「English」 로 적는다 — 카탈로그를 지나지 않는다.
    var nativeName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        }
    }
}

/// 설정 앱의 이 앱 화면 주소. `UIApplication` 은 리듀서에 두지 않으므로(SwiftLint `reducer_no_ui_types`) 여기서 읽는다.
enum AppSettingsURL {
    @MainActor
    static func current() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
