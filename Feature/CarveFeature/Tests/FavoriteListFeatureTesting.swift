//
//  FavoriteListFeatureTesting.swift
//  CarveFeatureTest
//
//  즐겨찾기 목록(시안 N4 · N5) — 조회 · 해제와 실행 취소 · 실패 되돌림 · 필사 화면으로 이동.
//  저장소는 `FavoriteRepositorySpy`(CarveDetailFavoriteTesting.swift)다.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("즐겨찾기 목록 (시안 N4 · N5)")
@MainActor
struct FavoriteListFeatureTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)

    private static func favorite(verse: Int, createdAt seconds: TimeInterval) -> FavoriteVerseSnapshot {
        FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: chapter, verse: verse),
            sentence: "\(verse)절 본문",
            lineData: nil,
            createdDate: Date(timeIntervalSince1970: seconds)
        )
    }

    private static let newer = favorite(verse: 1, createdAt: 200)
    private static let older = favorite(verse: 2, createdAt: 100)

    private func makeStore(
        spy: FavoriteRepositorySpy,
        clock: TestClock<Duration> = TestClock(),
        loaded favorites: [FavoriteVerseSnapshot]? = nil
    ) -> TestStoreOf<FavoriteListFeature> {
        var state = FavoriteListFeature.State()
        if let favorites {
            state.favorites = IdentifiedArray(uniqueElements: favorites)
            state.hasLoaded = true
        }
        return TestStore(initialState: state) {
            FavoriteListFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = spy
            $0.continuousClock = clock
        }
    }

    @Test("화면이 나타나면 최근 추가순 목록을 읽는다")
    func taskLoadsNewestFirst() async {
        let spy = FavoriteRepositorySpy()
        let seeded = [Self.older, Self.newer]
        spy.stored.setValue(seeded)
        let store = makeStore(spy: spy)

        await store.send(.view(.task))
        await store.receive(\.favoritesLoaded) {
            $0.favorites = [Self.newer, Self.older]
            $0.hasLoaded = true
        }
    }

    @Test("조회에 실패하면 빈 목록과 구분하고, 「다시 시도」 로 다시 읽는다")
    func loadFailureCanRetry() async {
        let spy = FavoriteRepositorySpy()
        let seeded = [Self.newer]
        spy.stored.setValue(seeded)
        spy.failures.setValue(1)
        let store = makeStore(spy: spy)

        await store.send(.view(.task))
        await store.receive(\.favoritesLoaded) {
            $0.hasLoaded = true
            $0.loadFailed = true
        }

        await store.send(.view(.retryLoadTapped))
        await store.receive(\.favoritesLoaded) {
            $0.favorites = [Self.newer]
            $0.loadFailed = false
        }
    }

    @Test("별을 누르면 목록에서 빼고 저장소에서 지우며 「실행 취소」 안내를 띄운다 — 안내는 잠시 뒤 사라진다")
    func unfavoriteRemovesAndOffersUndo() async {
        let spy = FavoriteRepositorySpy()
        let clock = TestClock()
        let store = makeStore(spy: spy, clock: clock, loaded: [Self.newer, Self.older])

        await store.send(.view(.unfavoriteTapped(Self.newer.key))) {
            $0.favorites = [Self.older]
            $0.notice = .removed(Self.newer)
        }
        await store.receive(\.removeFinished)
        await store.receive(\.delegate.favoritesChanged)
        #expect(spy.removed.value == [Self.newer.key])

        await clock.advance(by: FavoriteListFeature.removedNoticeDuration)
        await store.receive(\.noticeExpired) {
            $0.notice = nil
        }
    }

    @Test("「실행 취소」 는 같은 항목을 추가 시각 그대로 다시 저장해 원래 자리로 되돌린다")
    func undoRestoresAtOriginalPosition() async {
        let spy = FavoriteRepositorySpy()
        let store = makeStore(spy: spy, loaded: [Self.newer, Self.older])

        await store.send(.view(.unfavoriteTapped(Self.newer.key))) {
            $0.favorites = [Self.older]
            $0.notice = .removed(Self.newer)
        }
        await store.receive(\.removeFinished)
        await store.receive(\.delegate.favoritesChanged)

        await store.send(.view(.noticeActionTapped)) {
            $0.notice = nil
            $0.favorites = [Self.newer, Self.older]
        }
        await store.receive(\.restoreFinished)
        await store.receive(\.delegate.favoritesChanged)
        #expect(spy.saved.value == [Self.newer])
    }

    @Test("해제에 실패하면 항목을 제자리에 되돌리고, 「다시 시도」 는 다시 해제한다")
    func removeFailureRestoresItemAndRetries() async {
        let spy = FavoriteRepositorySpy()
        spy.failures.setValue(1)
        let clock = TestClock()
        let store = makeStore(spy: spy, clock: clock, loaded: [Self.newer, Self.older])

        await store.send(.view(.unfavoriteTapped(Self.older.key))) {
            $0.favorites = [Self.newer]
            $0.notice = .removed(Self.older)
        }
        await store.receive(\.removeFinished) {
            $0.favorites = [Self.newer, Self.older]
            $0.notice = .removeFailed(Self.older.key)
        }

        await store.send(.view(.noticeActionTapped)) {
            $0.favorites = [Self.newer]
            $0.notice = .removed(Self.older)
        }
        await store.receive(\.removeFinished)
        await store.receive(\.delegate.favoritesChanged)
        #expect(spy.removed.value == [Self.older.key])

        await clock.advance(by: FavoriteListFeature.removedNoticeDuration)
        await store.receive(\.noticeExpired) {
            $0.notice = nil
        }
    }

    @Test("「말씀으로 이동」 은 그 절을 보존한 본문과 함께 부모에 넘긴다")
    func openVerseDelegatesVerse() async {
        let store = makeStore(spy: FavoriteRepositorySpy(), loaded: [Self.newer])

        await store.send(.view(.openVerseTapped(Self.newer.key)))
        await store.receive(\.delegate.openVerse, BibleVerse(title: Self.chapter, verse: 1, sentence: "1절 본문"))
    }

    @Test("빈 목록의 「말씀 보러 가기」 는 필사 화면으로 돌아간다")
    func backToWritingDelegates() async {
        let store = makeStore(spy: FavoriteRepositorySpy(), loaded: [])

        await store.send(.view(.backToWritingTapped))
        await store.receive(\.delegate.backToWriting)
    }

    @Test("추가 날짜는 올해면 월 · 일만, 다른 해면 연도까지 적는다")
    func addedDateTextOmitsCurrentYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)))
        let thisYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9)))
        let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23)))

        #expect(FavoriteListView.addedDateText(thisYear, now: now, calendar: calendar) == "9월 15일 추가")
        #expect(FavoriteListView.addedDateText(lastYear, now: now, calendar: calendar) == "2025년 12월 31일 추가")
    }
}
