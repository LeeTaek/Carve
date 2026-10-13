//
//  LanguageSettingsSupport.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import Foundation
import UIKit

extension AppLanguage {
    /// 이 실행을 시작할 때의 화면 언어 — 이 모듈 번들이 고른 현지화(iOS 앱별 언어 · 기기 언어)다.
    /// 앱 안에서 바꾼 언어는 `appLanguageOverride` 에 있다.
    static var launch: Self {
        current(preferredLocalizations: Bundle.module.preferredLocalizations)
    }
}

extension AppLanguageSelection {
    /// 고르기 항목 이름. 언어는 그 언어로 적고(「한국어」 · 「English」), 시스템 설정만 화면 언어로 옮긴다.
    var title: String {
        switch self {
        case .system: SettingsCatalog.string("시스템 설정")
        case .korean: AppLanguage.korean.nativeName
        case .english: AppLanguage.english.nativeName
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
