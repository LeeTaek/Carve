//
//  FavoriteListWidgetTesting.swift
//  CarveFeatureTest
//
//  즐겨찾기 목록의 위젯 표시(시안 N6 배지 · 메뉴, N9 해제 확인).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("N6 · N9 — 즐겨찾기 목록의 위젯 표시")
@MainActor
struct FavoriteListWidgetTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let first = FavoriteVerseKey(chapter: chapter, verse: 1)
    private static let second = FavoriteVerseKey(chapter: chapter, verse: 2)

    private static func favorite(_ key: FavoriteVerseKey, at seconds: TimeInterval) -> FavoriteVerseSnapshot {
        FavoriteVerseSnapshot(
            key: key,
            sentence: "\(key.verse)절 본문",
            lineData: nil,
            createdDate: Date(timeIntervalSince1970: seconds)
        )
    }

    private func makeStore(
        repository: FavoriteRepositorySpy,
        widget: WidgetVerseClientSpy
    ) -> StoreOf<FavoriteListFeature> {
        Store(initialState: .initialState) {
            FavoriteListFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = repository
            $0.widgetVerseClient = widget
            $0.continuousClock = TestClock()
        }
    }

    private func loadedStore(
        repository: FavoriteRepositorySpy = FavoriteRepositorySpy(),
        widget: WidgetVerseClientSpy = WidgetVerseClientSpy()
    ) async throws -> StoreOf<FavoriteListFeature> {
        // `setValue` 는 Sendable 클로저로 받는다 — MainActor 인 도우미를 먼저 계산해 넣는다.
        let favorites = [Self.favorite(Self.first, at: 20), Self.favorite(Self.second, at: 10)]
        repository.stored.setValue(favorites)
        let store = makeStore(repository: repository, widget: widget)
        store.send(.view(.task))
        try await waitUntil { store.hasLoaded }
        return store
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("목록을 열면 지금 위젯에 표시 중인 말씀에 배지가 붙는다")
    func loadsWidgetSelection() async throws {
        let widget = WidgetVerseClientSpy()
        widget.current.setValue(WidgetVerseSelection(key: Self.second, designatedAt: WidgetVerseClientSpy.designatedAt))
        let store = try await loadedStore(widget: widget)

        try await waitUntil { store.widgetKey == Self.second }
    }

    @Test("더보기에서 고르면 그 말씀을 위젯에 표시하고, 다시 고르면 해제한다")
    func widgetTappedTogglesSelection() async throws {
        let widget = WidgetVerseClientSpy()
        let store = try await loadedStore(widget: widget)

        store.send(.view(.widgetTapped(Self.first)))
        try await waitUntil { store.notice == .widgetDisplayed }
        #expect(store.widgetKey == Self.first)
        #expect(widget.selected.value.map(\.key) == [Self.first])

        store.send(.view(.widgetTapped(Self.first)))
        try await waitUntil { store.notice == .widgetCleared }
        #expect(store.widgetKey == nil)
        #expect(widget.cleared.value == 1)
    }

    @Test("표시하지 못하면 배지를 위젯 쪽 값으로 되돌리고 「다시 시도」 를 둔다")
    func failureRestoresBadge() async throws {
        let widget = WidgetVerseClientSpy()
        widget.failures.setValue(1)
        let store = try await loadedStore(widget: widget)

        store.send(.view(.widgetTapped(Self.first)))
        try await waitUntil {
            if case .widgetFailed = store.notice { return true }
            return false
        }
        try await waitUntil { store.widgetKey == nil }

        store.send(.view(.noticeActionTapped))
        try await waitUntil { store.notice == .widgetDisplayed }
        #expect(store.widgetKey == Self.first)
    }

    @Test("위젯에 표시 중인 말씀을 해제하려 하면 먼저 확인하고, 해제하면 위젯에서도 내린다")
    func removingDisplayedFavoriteAsksFirst() async throws {
        let repository = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        widget.current.setValue(WidgetVerseSelection(key: Self.first, designatedAt: WidgetVerseClientSpy.designatedAt))
        let store = try await loadedStore(repository: repository, widget: widget)
        try await waitUntil { store.widgetKey == Self.first }

        store.send(.view(.unfavoriteTapped(Self.first)))
        #expect(store.removeConfirm != nil)
        #expect(store.favorites[id: Self.first] != nil)

        store.send(.removeConfirm(.presented(.confirm(Self.first))))
        try await waitUntil { repository.removed.value == [Self.first] }
        #expect(store.widgetKey == nil)
        try await waitUntil { widget.cleared.value == 1 }
    }

    @Test("위젯에 없는 말씀은 확인 없이 바로 해제한다")
    func removingOtherFavoriteSkipsConfirm() async throws {
        let repository = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        widget.current.setValue(WidgetVerseSelection(key: Self.first, designatedAt: WidgetVerseClientSpy.designatedAt))
        let store = try await loadedStore(repository: repository, widget: widget)
        try await waitUntil { store.widgetKey == Self.first }

        store.send(.view(.unfavoriteTapped(Self.second)))

        #expect(store.removeConfirm == nil)
        try await waitUntil { repository.removed.value == [Self.second] }
        #expect(store.widgetKey == Self.first)
        #expect(widget.cleared.value == 0)
    }
}
