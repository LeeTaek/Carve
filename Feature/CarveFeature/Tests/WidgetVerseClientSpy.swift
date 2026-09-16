//
//  WidgetVerseClientSpy.swift
//  CarveFeatureTest
//
//  위젯에 담은 말씀을 기록하는 스텁. 필사 화면(N6)과 즐겨찾기 목록(N6 · N9) 테스트가 함께 쓴다.
//

import Domain
import Foundation

import ComposableArchitecture

final class WidgetVerseClientSpy: WidgetVerseClient, @unchecked Sendable {
    struct Boom: Error { }

    /// 지금 위젯에 담긴 말씀들. 테스트가 미리 넣어 둘 수 있다.
    let current = LockIsolated<[FavoriteVerseKey]>([])
    /// 더하기 요청을 받은 순서.
    let added = LockIsolated<[FavoriteVerseSnapshot]>([])
    /// 빼기 요청을 받은 순서.
    let removed = LockIsolated<[FavoriteVerseKey]>([])
    /// 목록 맞추기 요청을 받은 순서.
    let selected = LockIsolated<[[FavoriteVerseSnapshot]]>([])
    /// 전부 빼기 요청 횟수.
    let cleared = LockIsolated(0)
    /// 남은 실패 횟수. 조회(`selection`)는 세지 않는다.
    let failures = LockIsolated(0)

    func selection() async -> [FavoriteVerseKey] {
        current.value
    }

    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {
        try failIfNeeded()
        guard favorites.count <= WidgetVerseLimit.maximum else { throw WidgetVerseLimitExceeded() }
        selected.withValue { $0.append(favorites) }
        current.setValue(favorites.map(\.key))
    }

    func add(_ favorite: FavoriteVerseSnapshot) async throws {
        try failIfNeeded()
        guard !current.value.contains(favorite.key) else { return }
        guard current.value.count < WidgetVerseLimit.maximum else { throw WidgetVerseLimitExceeded() }
        added.withValue { $0.append(favorite) }
        current.withValue { $0.append(favorite.key) }
    }

    func remove(_ key: FavoriteVerseKey) async throws {
        try failIfNeeded()
        removed.withValue { $0.append(key) }
        current.withValue { $0.removeAll { $0 == key } }
    }

    func clear() async throws {
        try failIfNeeded()
        cleared.withValue { $0 += 1 }
        current.setValue([])
    }

    private func failIfNeeded() throws {
        let shouldFail = failures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw Boom() }
    }
}
