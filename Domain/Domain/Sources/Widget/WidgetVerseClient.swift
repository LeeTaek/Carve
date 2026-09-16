//
//  WidgetVerseClient.swift
//  Domain
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// 지금 위젯에 표시 중인 말씀.
public struct WidgetVerseSelection: Equatable, Sendable {
    /// 표시 중인 즐겨찾기.
    public let key: FavoriteVerseKey
    /// 표시하도록 지정한 시각.
    public let designatedAt: Date

    public init(key: FavoriteVerseKey, designatedAt: Date) {
        self.key = key
        self.designatedAt = designatedAt
    }
}

/// 홈 화면 위젯에 표시할 말씀 하나를 정한다(시안 N6~N9).
///
/// 즐겨찾기가 보관함이고, 그중 **한 말씀을 명시적으로 골라** 위젯에 표시한다(2026-09-16 디자인 결정).
/// 선택은 **이 기기에만** 둔다(2026-09-16 사용자 결정) — 위젯 이미지가 기기 안 App Group 에 있기 때문이다.
/// 지정하면 그때의 본문 · 필기 사본을 위젯이 읽는 자리에 써 두고, 이후 원래 필사를 고쳐도 위젯은 바뀌지 않는다.
/// - App Group 에 쓰고 위젯을 깨우는 구현은 App 타겟에서 한다.
public protocol WidgetVerseClient: Sendable {
    /// 지금 위젯에 표시 중인 말씀. 없으면 nil.
    func selection() async -> WidgetVerseSelection?
    /// 이 즐겨찾기를 위젯에 표시한다. 이미 다른 말씀이 있으면 바꾼다.
    func select(_ favorite: FavoriteVerseSnapshot) async throws
    /// 표시를 해제한다. 즐겨찾기 자체는 남는다.
    func clear() async throws
}

private enum WidgetVerseClientKey: DependencyKey {
    // 실제 구현은 App 이 주입한다. 주입하지 않은 곳(미리보기 · 테스트)은 위젯을 건드리지 않는다.
    static let liveValue: any WidgetVerseClient = UnavailableWidgetVerseClient()
    static let testValue: any WidgetVerseClient = UnavailableWidgetVerseClient()
}

public extension DependencyValues {
    /// 위젯에 표시할 말씀.
    var widgetVerseClient: any WidgetVerseClient {
        get { self[WidgetVerseClientKey.self] }
        set { self[WidgetVerseClientKey.self] = newValue }
    }
}

/// 위젯을 쓸 수 없는 자리 — 표시 중인 말씀이 없고, 지정하려 하면 실패로 알린다.
private struct UnavailableWidgetVerseClient: WidgetVerseClient {
    struct NotConfigured: Error {}

    func selection() async -> WidgetVerseSelection? { nil }

    func select(_ favorite: FavoriteVerseSnapshot) async throws {
        throw NotConfigured()
    }

    func clear() async throws {
        throw NotConfigured()
    }
}
