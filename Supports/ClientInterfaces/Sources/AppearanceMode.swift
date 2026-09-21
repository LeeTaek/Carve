//
//  AppearanceMode.swift
//  ClientInterfaces
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ComposableArchitecture

/// 앱의 화면 모드 — 시스템 설정을 따르거나 라이트 · 다크로 고정한다.
///
/// 필사 영역(종이 · 원문 · PencilKit 캔버스)은 어느 모드에서도 라이트로 그린다(결정 8-1 안 1).
/// 원시값을 `UserDefaults` 에 저장하므로 case 이름을 바꾸면 사용자가 고른 값을 잃는다.
public enum AppearanceMode: String, CaseIterable, Hashable, Sendable {
    /// 기기의 라이트 · 다크 설정을 따른다.
    case system
    case light
    case dark
}

public extension SharedReaderKey where Self == AppStorageKey<AppearanceMode>.Default {
    /// 사용자가 고른 화면 모드(UserDefaults). 고른 적이 없으면 시스템 설정을 따른다.
    ///
    /// 설정 화면이 쓰고, 앱 루트 화면이 읽어 창 전체의 외관을 정한다.
    /// ⚠️ `appStorage` 는 키가 없으면 첫 로드 때 기본값을 저장한다 — 기본값을 바꿔도 이미 앱을 연 사용자에게는 닿지 않는다.
    static var appearanceMode: Self {
        Self[.appStorage("appearanceMode"), default: .system]
    }
}
