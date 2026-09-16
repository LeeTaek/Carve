//
//  WidgetVerseClientSpy.swift
//  CarveFeatureTest
//
//  위젯에 표시할 말씀을 기록하는 스텁. 필사 화면(N6)과 즐겨찾기 목록(N6 · N9) 테스트가 함께 쓴다.
//

import Domain
import Foundation

import ComposableArchitecture

final class WidgetVerseClientSpy: WidgetVerseClient, @unchecked Sendable {
    struct Boom: Error {}

    /// 지금 표시 중인 말씀. 테스트가 미리 넣어 둘 수 있다.
    let current = LockIsolated<WidgetVerseSelection?>(nil)
    /// 지정 요청을 받은 순서.
    let selected = LockIsolated<[FavoriteVerseSnapshot]>([])
    /// 해제 요청 횟수.
    let cleared = LockIsolated(0)
    /// 남은 실패 횟수. 조회(`selection`)는 세지 않는다.
    let failures = LockIsolated(0)

    static let designatedAt = Date(timeIntervalSince1970: 500)

    func selection() async -> WidgetVerseSelection? {
        current.value
    }

    func select(_ favorite: FavoriteVerseSnapshot) async throws {
        try failIfNeeded()
        selected.withValue { $0.append(favorite) }
        current.setValue(WidgetVerseSelection(key: favorite.key, designatedAt: Self.designatedAt))
    }

    func clear() async throws {
        try failIfNeeded()
        cleared.withValue { $0 += 1 }
        current.setValue(nil)
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
