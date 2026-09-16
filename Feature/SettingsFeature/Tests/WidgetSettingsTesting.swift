//
//  WidgetSettingsTesting.swift
//  SettingsFeatureTest
//
//  설정 → 위젯(시안 N7 · N8) — 지금 담긴 말씀들, 즐겨찾기에서 여럿 고르기, 모두 빼기.
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

/// 위젯에 담은 말씀을 기록하는 스텁.
private final class WidgetSpy: WidgetVerseClient, @unchecked Sendable {
    let current = LockIsolated<[FavoriteVerseKey]>([])
    let selected = LockIsolated<[[FavoriteVerseSnapshot]]>([])
    let cleared = LockIsolated(0)

    func selection() async -> [FavoriteVerseKey] { current.value }

    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {
        selected.withValue { $0.append(favorites) }
        current.setValue(favorites.map(\.key))
    }

    func add(_ favorite: FavoriteVerseSnapshot) async throws {
        current.withValue { $0.append(favorite.key) }
    }

    func remove(_ key: FavoriteVerseKey) async throws {
        current.withValue { $0.removeAll { $0 == key } }
    }

    func clear() async throws {
        cleared.withValue { $0 += 1 }
        current.setValue([])
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

    @Test("화면을 열면 지금 위젯에 담긴 말씀들을 보여 준다 — 즐겨찾기에서 사라진 말씀은 뺀다")
    func showsSelectedVerses() async throws {
        let widget = WidgetSpy()
        let gone = FavoriteVerseKey(chapter: Self.chapter, verse: 9)
        widget.current.setValue([Self.second, gone])
        let store = makeStore(
            favorites: FavoritesStub([Self.favorite(Self.first), Self.favorite(Self.second)]),
            widget: widget
        )

        store.send(.view(.task))
        try await waitUntil { store.hasLoaded }

        #expect(store.selected == [Self.favorite(Self.second)])
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
        store.send(.view(.pickerToggled(Self.first)))
        store.send(.view(.setPickerPresented(false)))
        #expect(widget.selected.value.isEmpty)
        #expect(store.selected.isEmpty)

        store.send(.view(.changeTapped))
        store.send(.view(.pickerToggled(Self.first)))
        store.send(.view(.pickerToggled(Self.second)))
        store.send(.view(.pickerApplyTapped))
        try await waitUntil { store.selected.count == 2 }

        // 담는 순서는 목록 순서(최근 추가순)를 따른다.
        #expect(widget.selected.value == [[Self.favorite(Self.first), Self.favorite(Self.second)]])
        #expect(store.isPickerPresented == false)
    }

    @Test("고르는 시트에서 다시 누르면 선택이 풀린다")
    func toggleRemovesSelection() async throws {
        let widget = WidgetSpy()
        widget.current.setValue([Self.first, Self.second])
        let store = makeStore(
            favorites: FavoritesStub([Self.favorite(Self.first), Self.favorite(Self.second)]),
            widget: widget
        )
        store.send(.view(.task))
        try await waitUntil { store.selected.count == 2 }

        store.send(.view(.changeTapped))
        #expect(store.pickerSelection == [Self.first, Self.second])
        store.send(.view(.pickerToggled(Self.second)))
        store.send(.view(.pickerApplyTapped))
        try await waitUntil { store.selected == [Self.favorite(Self.first)] }
    }

    @Test("상한을 넘겨 고를 수 없다")
    func pickerStopsAtLimit() async throws {
        let keys = (1...(WidgetVerseLimit.maximum + 2)).map { FavoriteVerseKey(chapter: Self.chapter, verse: $0) }
        let widget = WidgetSpy()
        let store = makeStore(favorites: FavoritesStub(keys.map(Self.favorite)), widget: widget)
        store.send(.view(.task))
        try await waitUntil { store.hasLoaded }

        store.send(.view(.changeTapped))
        for key in keys {
            store.send(.view(.pickerToggled(key)))
        }

        #expect(store.pickerSelection.count == WidgetVerseLimit.maximum)
        #expect(store.canSelectMore == false)
    }

    @Test("모두 빼면 담긴 말씀이 없어진다")
    func clearRemovesSelection() async throws {
        let widget = WidgetSpy()
        widget.current.setValue([Self.first])
        let store = makeStore(favorites: FavoritesStub([Self.favorite(Self.first)]), widget: widget)
        store.send(.view(.task))
        try await waitUntil { !store.selected.isEmpty }

        store.send(.view(.clearTapped))
        try await waitUntil { store.selected.isEmpty }

        #expect(widget.cleared.value == 1)
    }
}
