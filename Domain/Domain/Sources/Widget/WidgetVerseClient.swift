//
//  WidgetVerseClient.swift
//  Domain
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// 위젯에 담을 수 있는 말씀 수의 상한(2026-09-16 사용자 결정).
///
/// 지정할 때 필기 사본 PNG 를 기기에 함께 저장하므로 무제한으로 두지 않는다.
public enum WidgetVerseLimit {
    /// 담을 수 있는 최대 개수.
    public static let maximum = 20
}

/// 상한을 넘겨 담으려 했다.
public struct WidgetVerseLimitExceeded: Error, Equatable {
    public init() { }
}

/// 홈 화면 위젯이 돌릴 말씀들을 정한다(시안 N6~N9).
///
/// 즐겨찾기가 보관함이고, 그중 **여러 말씀을 골라** 위젯에 담는다. 위젯은 담은 말씀을
/// 1시간마다 한 바퀴씩 돌며 보여 준다([WidgetVerseRotation] — 2026-09-16 사용자 결정).
/// 선택은 **이 기기에만** 둔다(2026-09-16 사용자 결정) — 위젯 이미지가 기기 안 App Group 에 있기 때문이다.
/// 담으면 그때의 본문 · 필기 사본을 위젯이 읽는 자리에 써 두고, 이후 원래 필사를 고쳐도 위젯은 바뀌지 않는다.
/// - App Group 에 쓰고 위젯을 깨우는 구현은 App 타겟에서 한다.
public protocol WidgetVerseClient: Sendable {
    /// 지금 위젯이 돌리는 말씀들. 담은 순서다.
    func selection() async -> [FavoriteVerseKey]
    /// 위젯이 돌릴 말씀을 이 목록으로 맞춘다. 이미 담긴 말씀은 사본을 다시 만들지 않는다.
    /// - Throws: 상한을 넘으면 `WidgetVerseLimitExceeded`.
    func select(_ favorites: [FavoriteVerseSnapshot]) async throws
    /// 한 말씀을 더 담는다. 이미 담겨 있으면 아무것도 하지 않는다.
    /// - Throws: 상한을 넘으면 `WidgetVerseLimitExceeded`.
    func add(_ favorite: FavoriteVerseSnapshot) async throws
    /// 한 말씀을 뺀다. 담겨 있지 않으면 아무것도 하지 않는다.
    func remove(_ key: FavoriteVerseKey) async throws
    /// 전부 뺀다. 즐겨찾기 자체는 남는다.
    func clear() async throws
}

private enum WidgetVerseClientKey: DependencyKey {
    // 실제 구현은 App 이 주입한다. 주입하지 않은 곳(미리보기 · 테스트)은 위젯을 건드리지 않는다.
    static let liveValue: any WidgetVerseClient = UnavailableWidgetVerseClient()
    static let testValue: any WidgetVerseClient = UnavailableWidgetVerseClient()
}

public extension DependencyValues {
    /// 위젯에 담을 말씀들.
    var widgetVerseClient: any WidgetVerseClient {
        get { self[WidgetVerseClientKey.self] }
        set { self[WidgetVerseClientKey.self] = newValue }
    }
}

/// 위젯을 쓸 수 없는 자리 — 담긴 말씀이 없고, 담으려 하면 실패로 알린다.
private struct UnavailableWidgetVerseClient: WidgetVerseClient {
    struct NotConfigured: Error { }

    func selection() async -> [FavoriteVerseKey] { [] }

    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {
        throw NotConfigured()
    }

    func add(_ favorite: FavoriteVerseSnapshot) async throws {
        throw NotConfigured()
    }

    func remove(_ key: FavoriteVerseKey) async throws {
        throw NotConfigured()
    }

    func clear() async throws {
        throw NotConfigured()
    }
}
