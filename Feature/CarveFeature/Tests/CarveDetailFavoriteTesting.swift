//
//  CarveDetailFavoriteTesting.swift
//  CarveFeatureTest
//
//  즐겨찾기(시안 N1 · N2) — 필사 화면 배선. 절 메뉴의 즐겨찾기가 **추가 당시의** 본문 · 필기를 저장하는지,
//  표시가 저장을 기다리지 않고 바뀌고 실패하면 되돌아가는지, 장이 바뀌면 그 장의 즐겨찾기를 읽는지.
//  `CarveDetailFeature.State` 는 Equatable 이 아니라 TestStore 대신 실제 Store 로 상태 전이를 본다.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

// MARK: - 스텁

/// 호출을 기록하는 즐겨찾기 저장소. `failures` 만큼 다음 쓰기 · 목록 조회를 실패시킨다.
final class FavoriteRepositorySpy: FavoriteVerseRepository, @unchecked Sendable {
    let stored = LockIsolated<[FavoriteVerseSnapshot]>([])
    let saved = LockIsolated<[FavoriteVerseSnapshot]>([])
    let removed = LockIsolated<[FavoriteVerseKey]>([])
    let loadedChapters = LockIsolated<[BibleChapter]>([])
    /// 남은 실패 횟수. 장의 절 조회(`favoriteVerses`)는 세지 않는다.
    let failures = LockIsolated(0)

    struct Boom: Error {}

    /// 다음 `favoriteVerses` 를 `releaseLoad()` 까지 붙잡는다. 결과는 **부른 시점**의 저장소 내용이다 — 늦게 도착하는 옛 조회.
    private let holdNextLoad = LockIsolated(false)
    let loadGate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)
    func holdNextLoadCall() { holdNextLoad.setValue(true) }
    func releaseLoad() {
        loadGate.withValue { $0?.yield(); $0?.finish(); $0 = nil }
    }

    func favoriteVerses(in chapter: BibleChapter, translation: Translation) async throws -> Set<Int> {
        loadedChapters.withValue { $0.append(chapter) }
        let verses = Set(stored.value
            .filter { $0.key.chapter == chapter && $0.key.translation == translation }
            .map(\.key.verse))
        if holdNextLoad.withValue({ let hold = $0; $0 = false; return hold }) {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            loadGate.setValue(continuation)
            for await _ in stream { break }
        }
        return verses
    }

    func favorites() async throws -> [FavoriteVerseSnapshot] {
        try failIfNeeded()
        return stored.value.sorted { $0.createdDate > $1.createdDate }
    }

    func save(_ favorite: FavoriteVerseSnapshot) async throws {
        try failIfNeeded()
        saved.withValue { $0.append(favorite) }
        stored.withValue { rows in
            rows.removeAll { $0.key == favorite.key }
            rows.append(favorite)
        }
    }

    func remove(_ key: FavoriteVerseKey) async throws {
        try failIfNeeded()
        removed.withValue { $0.append(key) }
        stored.withValue { rows in
            rows.removeAll { $0.key == key }
        }
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

// MARK: - 필사 화면

@Suite("즐겨찾기 — 필사 화면 배선 (시안 N1 · N2)")
@MainActor
struct CarveDetailFavoriteTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let firstVerse = "여호와는 나의 목자시니 내가 부족함이 없으리로다"
    private static let now = Date(timeIntervalSince1970: 1_000)

    private static func state(favorites: Set<Int> = []) -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        state.sentenceWithDrawingState = [
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: chapter, verse: 1, sentence: firstVerse), drawing: nil),
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: chapter, verse: 2, sentence: "그가 나를 푸른 초장에 누이시며"), drawing: nil)
        ]
        state.favoriteChapter = chapter
        state.favoriteVerses = favorites
        return state
    }

    private func makeStore(
        spy: FavoriteRepositorySpy,
        clock: TestClock<Duration> = TestClock(),
        favorites: Set<Int> = []
    ) -> StoreOf<CarveDetailFeature> {
        Store(initialState: Self.state(favorites: favorites)) {
            CarveDetailFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = spy
            $0.continuousClock = clock
            $0.date = .constant(Self.now)
            $0.drawingRepository = RepositorySpy()
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.uuid = .incrementing
            // `setSentence` 가 `undoManager.clear()` 를 부른다 — 테스트값이 없는 의존성이라 주입한다.
            $0.undoManager = SharedUndoManager()
        }
    }

    /// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
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

    @Test("추가하면 표시가 곧바로 켜지고, 추가 당시의 본문 · 필기 · 시각이 저장되며 안내가 잠깐 뜬다")
    func addingFavoriteSavesSnapshotAndShowsNotice() async throws {
        let spy = FavoriteRepositorySpy()
        let clock = TestClock()
        let store = makeStore(spy: spy, clock: clock)
        let ink = Data([1, 2, 3])

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: ink)))))
        // 저장을 기다리지 않고 표시부터 바뀐다.
        #expect(store.favoriteVerses == [1])

        try await waitUntil { store.favoriteNotice == .added }
        #expect(spy.saved.value == [
            FavoriteVerseSnapshot(
                key: FavoriteVerseKey(chapter: Self.chapter, verse: 1),
                sentence: Self.firstVerse,
                lineData: ink,
                createdDate: Self.now
            )
        ])

        // 안내는 잠시 뒤 사라진다.
        try await Task.sleep(for: .milliseconds(50))
        await clock.advance(by: CarveDetailFeature.favoriteAddedNoticeDuration)
        try await waitUntil { store.favoriteNotice == nil }
    }

    @Test("이미 즐겨찾기한 절을 다시 고르면 해제한다 — 표시만 꺼지고 안내는 없다")
    func togglingExistingFavoriteRemovesIt() async throws {
        let spy = FavoriteRepositorySpy()
        let store = makeStore(spy: spy, favorites: [2])

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 2, ink: Data([9]))))))
        #expect(store.favoriteVerses.isEmpty)

        try await waitUntil { spy.removed.value == [FavoriteVerseKey(chapter: Self.chapter, verse: 2)] }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.favoriteNotice == nil)
        #expect(spy.saved.value.isEmpty)
    }

    @Test("저장에 실패하면 표시를 되돌리고 알리며, 「다시 시도」 는 같은 항목을 다시 저장한다")
    func failedSaveRevertsAndRetriesSameSnapshot() async throws {
        let spy = FavoriteRepositorySpy()
        spy.failures.setValue(1)
        let store = makeStore(spy: spy)
        let ink = Data([4, 5])

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: ink)))))
        try await waitUntil {
            if case .failed = store.favoriteNotice { return true }
            return false
        }
        #expect(store.favoriteVerses.isEmpty)
        #expect(spy.saved.value.isEmpty)

        store.send(.view(.favoriteRetryTapped))
        #expect(store.favoriteVerses == [1])
        try await waitUntil { store.favoriteNotice == .added }
        #expect(spy.saved.value.map(\.lineData) == [ink])
    }

    @Test("본문이 정해지면 그 장의 즐겨찾기를 읽고, 다른 장이면 이전 장의 표시부터 비운다")
    func settingSentenceLoadsChapterFavorites() async throws {
        let spy = FavoriteRepositorySpy()
        let other = BibleChapter(title: .psalms, chapter: 24)
        let seeded = FavoriteVerseSnapshot(key: FavoriteVerseKey(chapter: other, verse: 3), sentence: "", lineData: nil, createdDate: Self.now)
        spy.stored.setValue([seeded])
        let store = makeStore(spy: spy, favorites: [1])

        store.send(.setSentence([BibleVerse(title: other, verse: 3, sentence: "여호와의 산에 오를 자가 누구며")], []))
        #expect(store.favoriteChapter == other)
        // 이전 장(23편)의 표시를 새 장 본문에 남기지 않는다.
        #expect(store.favoriteVerses.isEmpty)

        try await waitUntil { store.favoriteVerses == [3] }
        #expect(spy.loadedChapters.value == [other])
    }

    @Test("목록에서 바뀌었다는 알림을 받으면 지금 장의 즐겨찾기를 다시 읽는다")
    func reloadFavoritesReadsCurrentChapter() async throws {
        let spy = FavoriteRepositorySpy()
        // 목록에서 두 절을 모두 해제한 뒤다 — 저장소는 비었고 필사 화면 표시는 아직 옛 값이다.
        let store = makeStore(spy: spy, favorites: [1, 2])

        store.send(.reloadFavorites)

        try await waitUntil { store.favoriteVerses.isEmpty }
        #expect(spy.loadedChapters.value == [Self.chapter])
    }

    @Test("조회를 시작한 뒤 이 화면에서 바꾼 것이 있으면, 늦게 온 조회 결과로 표시를 덮지 않는다")
    func staleLoadDoesNotOverrideLocalChange() async throws {
        let spy = FavoriteRepositorySpy()
        spy.holdNextLoadCall()
        let store = makeStore(spy: spy)

        // 저장소가 비어 있을 때 시작한 조회가 붙잡혀 있는 동안 1절을 추가한다.
        store.send(.reloadFavorites)
        try await waitUntil { spy.loadGate.value != nil }
        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: nil)))))
        try await waitUntil { store.favoriteNotice == .added }

        // 옛 조회 결과(빈 집합)가 늦게 도착해도 방금 켠 표시는 그대로다.
        spy.releaseLoad()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.favoriteVerses == [1])

        // 바꾼 뒤에 시작한 조회는 받아들인다 — 저장소에 들어간 1절이 그대로 읽힌다.
        store.send(.reloadFavorites)
        try await waitUntil { spy.loadedChapters.value.count == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.favoriteVerses == [1])
    }
}
