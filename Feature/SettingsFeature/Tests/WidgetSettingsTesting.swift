//
//  WidgetSettingsTesting.swift
//  SettingsFeatureTest
//
//  설정 → 위젯(시안 N7 · N8) — 지금 표시 중인 말씀, 즐겨찾기에서 고르기, 표시 해제.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

/// 즐겨찾기 보관본만 돌려주는 저장소 스텁.
private final class FavoritesStub: FavoriteVerseRepository, @unchecked Sendable {
    let stored: LockIsolated<[FavoriteVerseSnapshot]>

    init(_ favorites: [FavoriteVerseSnapshot]) {
        stored = LockIsolated(favorites)
    }

    func favoriteVerses(in chapter: BibleChapter, translation: Translation) async throws -> Set<Int> { [] }
    func favorites() async throws -> [FavoriteVerseSnapshot] { stored.value }
    func save(_ favorite: FavoriteVerseSnapshot) async throws {}
    func remove(_ key: FavoriteVerseKey) async throws {}
}

/// 위젯에 표시할 말씀을 기록하는 스텁.
private final class WidgetSpy: WidgetVerseClient, @unchecked Sendable {
    let current = LockIsolated<WidgetVerseSelection?>(nil)
    let selected = LockIsolated<[FavoriteVerseSnapshot]>([])
    let cleared = LockIsolated(0)

    func selection() async -> WidgetVerseSelection? { current.value }

    func select(_ favorite: FavoriteVerseSnapshot) async throws {
        selected.withValue { $0.append(favorite) }
        current.setValue(WidgetVerseSelection(key: favorite.key, designatedAt: Date(timeIntervalSince1970: 0)))
    }

    func clear() async throws {
        cleared.withValue { $0 += 1 }
        current.setValue(nil)
    }
}

@Suite("N7 · N8 — 설정의 위젯 화면")
@MainActor
struct WidgetSettingsTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let first = FavoriteVerseKey(chapter: chapter, verse: 1)
    private static let second = FavoriteVerseKey(chapter: chapter, verse: 2)

    private static func favorite(_ key: FavoriteVerseKey) -> FavoriteVerseSnapshot {
        FavoriteVerseSnapshot(
            key: key,
            sentence: "\(key.verse)절 본문",
            lineData: nil,
            createdDate: Date(timeIntervalSince1970: TimeInterval(key.verse))
        )
    }

    private func makeStore(favorites: FavoritesStub, widget: WidgetSpy) -> StoreOf<WidgetSettingsFeature> {
        Store(initialState: .initialState) {
            WidgetSettingsFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = favorites
            $0.widgetVerseClient = widget
        }
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

    @Test("화면을 열면 지금 위젯에 표시 중인 말씀을 보여 준다")
    func showsCurrentVerse() async throws {
        let widget = WidgetSpy()
        widget.current.setValue(WidgetVerseSelection(key: Self.second, designatedAt: Date(timeIntervalSince1970: 0)))
        let store = makeStore(
            favorites: FavoritesStub([Self.favorite(Self.first), Self.favorite(Self.second)]),
            widget: widget
        )

        store.send(.view(.task))
        try await waitUntil { store.hasLoaded }

        #expect(store.current == Self.favorite(Self.second))
    }

    @Test("고른 말씀은 「적용」 을 눌러야 바뀐다 — 취소하면 그대로 둔다")
    func applyChangesSelection() async throws {
        let widget = WidgetSpy()
        let store = makeStore(
            favorites: FavoritesStub([Self.favorite(Self.first), Self.favorite(Self.second)]),
            widget: widget
        )
        store.send(.view(.task))
        try await waitUntil { store.hasLoaded }

        store.send(.view(.changeTapped))
        store.send(.view(.pickerSelected(Self.first)))
        store.send(.view(.setPickerPresented(false)))
        #expect(widget.selected.value.isEmpty)
        #expect(store.current == nil)

        store.send(.view(.changeTapped))
        store.send(.view(.pickerSelected(Self.first)))
        store.send(.view(.pickerApplyTapped))
        try await waitUntil { store.current == Self.favorite(Self.first) }

        #expect(widget.selected.value == [Self.favorite(Self.first)])
        #expect(store.isPickerPresented == false)
    }

    @Test("표시를 해제하면 고른 말씀이 없어진다")
    func clearRemovesSelection() async throws {
        let widget = WidgetSpy()
        widget.current.setValue(WidgetVerseSelection(key: Self.first, designatedAt: Date(timeIntervalSince1970: 0)))
        let store = makeStore(favorites: FavoritesStub([Self.favorite(Self.first)]), widget: widget)
        store.send(.view(.task))
        try await waitUntil { store.current != nil }

        store.send(.view(.clearTapped))
        try await waitUntil { store.current == nil }

        #expect(widget.cleared.value == 1)
    }
}
