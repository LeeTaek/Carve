//
//  CarveDetailWidgetTesting.swift
//  CarveFeatureTest
//
//  절 메뉴 「위젯에 추가」(시안 N6) — 즐겨찾기에 없던 절은 지금 모습을 보관한 뒤 담고,
//  이미 보관된 절은 보관본을 그대로 쓴다. `CarveDetailFeature.State` 는 Equatable 이 아니라 실제 Store 로 본다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("N6 — 필사 화면에서 위젯에 추가")
@MainActor
struct CarveDetailWidgetTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let key = FavoriteVerseKey(chapter: chapter, verse: 1)
    private static let sentence = "여호와는 나의 목자시니 내가 부족함이 없으리로다"
    private static let now = Date(timeIntervalSince1970: 1_000)
    private static let ink = Data([1, 2, 3])
    private static let request = CarveDetailFeature.Action.scope(
        .chapterCanvasAction(.delegate(.widgetRequested(verse: 1, ink: ink)))
    )

    private static func state() -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        state.sentenceWithDrawingState = [
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: chapter, verse: 1, sentence: sentence), drawing: nil)
        ]
        state.favoriteChapter = chapter
        return state
    }

    private func makeStore(
        favorites: FavoriteRepositorySpy,
        widget: WidgetVerseClientSpy,
        clock: TestClock<Duration> = TestClock()
    ) -> StoreOf<CarveDetailFeature> {
        Store(initialState: Self.state()) {
            CarveDetailFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = favorites
            $0.widgetVerseClient = widget
            $0.continuousClock = clock
            $0.date = .constant(Self.now)
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

    @Test("즐겨찾기에 없던 절은 지금 본문 · 필기를 보관하고 위젯에 담는다 — 별 표시도 함께 켜진다")
    func newVerseIsArchivedAndDisplayed() async throws {
        let favorites = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        let clock = TestClock()
        let store = makeStore(favorites: favorites, widget: widget, clock: clock)

        store.send(Self.request)
        try await waitUntil { store.widgetNotice == .added(addedToFavorites: true) }

        let expected = FavoriteVerseSnapshot(key: Self.key, sentence: Self.sentence, lineData: Self.ink, createdDate: Self.now)
        #expect(favorites.saved.value == [expected])
        #expect(widget.added.value == [expected])
        #expect(store.favoriteVerses.contains(1))

        await clock.advance(by: CarveDetailFeature.widgetNoticeDuration)
        try await waitUntil { store.widgetNotice == nil }
    }

    @Test("이미 보관된 절은 보관본을 그대로 쓴다 — 다시 저장하지 않는다")
    func storedFavoriteIsReused() async throws {
        let favorites = FavoriteRepositorySpy()
        let stored = FavoriteVerseSnapshot(
            key: Self.key,
            sentence: "보관할 때의 본문",
            lineData: Data([9]),
            createdDate: Date(timeIntervalSince1970: 10)
        )
        favorites.stored.setValue([stored])
        let widget = WidgetVerseClientSpy()
        let store = makeStore(favorites: favorites, widget: widget)

        store.send(Self.request)
        try await waitUntil { store.widgetNotice == .added(addedToFavorites: false) }

        #expect(favorites.saved.value.isEmpty)
        #expect(widget.added.value == [stored])
    }

    @Test("담지 못하면 「다시 시도」 안내가 뜨고, 다시 시도하면 보관본으로 다시 담는다")
    func failureOffersRetry() async throws {
        let favorites = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        widget.failures.setValue(1)
        let store = makeStore(favorites: favorites, widget: widget)

        store.send(Self.request)
        try await waitUntil {
            if case .failed = store.widgetNotice { return true }
            return false
        }

        store.send(.view(.widgetRetryTapped))
        // 첫 시도에서 보관은 끝났으므로 두 번째는 보관본을 쓴다.
        try await waitUntil { store.widgetNotice == .added(addedToFavorites: false) }
        #expect(widget.added.value.count == 1)
        #expect(favorites.saved.value.count == 1)
    }

    @Test("이미 담긴 절을 다시 누르면 아무것도 바꾸지 않고 알려 준다")
    func alreadyAddedVerseIsUnchanged() async throws {
        let favorites = FavoriteRepositorySpy()
        let stored = FavoriteVerseSnapshot(
            key: Self.key, sentence: Self.sentence, lineData: nil, createdDate: Self.now
        )
        favorites.stored.setValue([stored])
        let widget = WidgetVerseClientSpy()
        widget.current.setValue([Self.key])
        let store = makeStore(favorites: favorites, widget: widget)

        store.send(Self.request)
        try await waitUntil { store.widgetNotice == .alreadyAdded }

        #expect(widget.added.value.isEmpty)
        #expect(favorites.saved.value.isEmpty)
    }

    @Test("위젯이 꽉 차면 즐겨찾기에도 담지 않고 상한을 알려 준다")
    func limitIsReported() async throws {
        let favorites = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        let full = (1...WidgetVerseLimit.maximum).map { FavoriteVerseKey(chapter: Self.chapter, verse: $0 + 100) }
        widget.current.setValue(full)
        let store = makeStore(favorites: favorites, widget: widget)

        store.send(Self.request)
        try await waitUntil { store.widgetNotice == .limitReached }

        #expect(widget.added.value.isEmpty)
        #expect(favorites.saved.value.isEmpty)
    }
}
