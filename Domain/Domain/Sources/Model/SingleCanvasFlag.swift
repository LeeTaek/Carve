//
//  SingleCanvasFlag.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 단일 Canvas(설계 §13 Phase 3) feature flag 의 저장 키 (§10-3 — flag off 가 유일한 롤백 수단).
///
/// `CarveFeature` 가 `@Shared(.appStorage(...))` 로 읽고, `SettingsFeature` 의 토글이 같은 키에 쓴다.
/// 두 모듈이 서로를 모르므로 키는 둘 다 의존하는 Domain 에 둔다.
public enum SingleCanvasFlag {
    /// `UserDefaults` 키. 기본값은 off.
    public static let appStorageKey = "singleCanvasEnabled"
    /// Debug 빌드에서 flag 와 같은 효과를 내는 실행 인자 (`xcrun simctl launch … -SingleCanvas`).
    public static let debugLaunchArgument = "-SingleCanvas"
}
