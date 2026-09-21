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
    /// `UserDefaults` 키.
    public static let appStorageKey = "singleCanvasEnabled"

    /// 키가 **없을 때** 쓰는 값 — 즉 아직 토글을 만진 적 없는 사용자의 경로.
    ///
    /// ⚠️ **읽는 쪽이 둘이라 여기 한 곳에 둔다.** `CarveFeature` 는 `@Shared(.appStorage)` 의 기본값으로,
    /// `SettingsFeature` 는 `UserDefaults` 를 직접 읽으며 쓴다. `UserDefaults.bool(forKey:)` 는 키가 없으면
    /// 무조건 `false` 라서, 두 곳이 따로 기본값을 갖고 있으면 **앱은 단일 Canvas 로 도는데 설정 화면은 OFF 로 보이는**
    /// 불일치가 생긴다 (설계 §10-3).
    public static let defaultValue = true
    /// Debug 빌드에서 flag 와 같은 효과를 내는 실행 인자 (`xcrun simctl launch … -SingleCanvas`).
    public static let debugLaunchArgument = "-SingleCanvas"
    /// 기존 저장값을 지웠는지 기록하는 `UserDefaults` 키 (`resetStoredValueOnce(in:)`).
    public static let storedValueResetKey = "singleCanvasStoredValueReset"

    /// 기존 사용자도 기본값(`defaultValue`, on)을 따르게 한다 — 설치당 한 번, flag 를 읽는 Store 를 만들기 전에 부른다.
    ///
    /// 기본값은 키가 **없을 때만** 쓰이므로, 값이 한 번이라도 저장된 사용자에게는 기본값을 바꿔도 닿지 않는다.
    /// 그래서 끈 값까지 포함해 저장값을 한 번 지운다. 지운 뒤 토글로 끈 값은 다시 지우지 않으므로 flag off 롤백 수단은 남는다.
    /// - Parameter defaults: flag 가 저장된 `UserDefaults`. 앱은 `@Shared(.appStorage)` 와 같은 `.standard` 를 넘긴다.
    public static func resetStoredValueOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: storedValueResetKey) else { return }
        defaults.removeObject(forKey: appStorageKey)
        defaults.set(true, forKey: storedValueResetKey)
    }
}
