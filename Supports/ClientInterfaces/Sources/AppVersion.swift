//
//  AppVersion.swift
//  ClientInterfaces
//
//  Created by Claude on 10/1/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

private enum AppVersionKey: DependencyKey {
    /// 앱 번들의 마케팅 버전(`CFBundleShortVersionString`). 읽지 못하면 빈 문자열이다.
    static let liveValue: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    /// 시험 기본값 — 버전이 없는 것으로 둔다. 버전을 보는 시험은 `$0.appVersion = "2.0.1"` 처럼 직접 정한다.
    static let testValue: String = ""
}

public extension DependencyValues {
    /// 지금 실행 중인 앱의 마케팅 버전(예: 「2.0.1」).
    ///
    /// 코디네이터가 필사 화면에 들어갈 때 마지막으로 본 버전(`lastSeenAppVersion`)과 견주어 패치노트를 띄울지 정한다.
    var appVersion: String {
        get { self[AppVersionKey.self] }
        set { self[AppVersionKey.self] = newValue }
    }
}
