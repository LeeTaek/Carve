//
//  TranslationFavoriteWidgetTesting.swift
//  CarveFeatureTest
//
//  영어 현지화(결정 1 · 11) — 절 메뉴의 즐겨찾기 · 위젯에 추가 · 이미지 저장과 이전 필사가 **지금 장의 번역본**으로 동작하는지.
//  KJV 장에서 고른 절은 KJV 키 · 약칭을 쓰고, 같은 권 · 장 · 절의 개역개정 즐겨찾기 · 필사 행과 섞이지 않는다.
//  `CarveDetailFeature.State` 는 Equatable 이 아니라 TestStore 대신 실제 Store 로 상태 전이를 본다.
//  저장소 스텁은 `FavoriteRepositorySpy`(CarveDetailFavoriteTesting.swift) · `WidgetVerseClientSpy` 를 그대로 쓴다.
//

import ClientInterfaces
import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import CarveFeature

// MARK: - 스텁

/// 늘 추가에 성공하는 사진 보관함.
private struct AlwaysAddingPhotoLibrary: PhotoLibraryClient {
    func addImage(_ imageData: Data) async throws -> PhotoLibraryAddOutcome { .added }
}

/// 이전 필사 시험의 잉크 — `PKDrawing` 바이트는 만들 때마다 달라지므로 한 번 만들어 재사용한다. 행마다 내용이 달라 묶이지 않는다.
private let nkrvRowInk = translationHistoryInk(y: 10)
private let kjvOlderInk = translationHistoryInk(y: 40)
private let kjvCurrentInk = translationHistoryInk(y: 70)

/// 획 하나짜리 필기 — 목록은 획 없는 행을 거른다(`DrawingContentRule.hasStrokes`).
private func translationHistoryInk(y offset: Double) -> Data {
    let points = (0..<8).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index) * 10, y: offset), timeOffset: Double(index) * 0.02,
            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
}

// MARK: - 시험

@Suite("영어 현지화 — 즐겨찾기 · 위젯 · 이미지 저장 · 이전 필사를 번역본별로")
@MainActor
struct TranslationFavoriteWidgetTesting {
    // `LockIsolated.setValue` 의 Sendable 클로저에서 읽으므로 MainActor 에 두지 않는다(값 타입 상수).
    private nonisolated static let kjvChapter = BibleChapter(title: .psalms, chapter: 23, translation: .KJV)
    private nonisolated static let nkrvChapter = BibleChapter(title: .psalms, chapter: 23)
    private nonisolated static let kjvKey = FavoriteVerseKey(chapter: kjvChapter, verse: 1)
    private nonisolated static let nkrvKey = FavoriteVerseKey(chapter: nkrvChapter, verse: 1)
    private nonisolated static let kjvSentence = "The LORD is my shepherd; I shall not want."
    private nonisolated static let now = Date(timeIntervalSince1970: 1_000)
    /// 같은 절(시편 23:1)의 개역개정 즐겨찾기 — KJV 장에서 한 일과 따로 남아야 한다.
    private nonisolated static let nkrvFavorite = FavoriteVerseSnapshot(
        key: nkrvKey, sentence: "여호와는 나의 목자시니 내가 부족함이 없으리로다",
        lineData: Data([7]), createdDate: Date(timeIntervalSince1970: 10)
    )

    /// KJV 시편 23편을 연 필사 화면 — 본문 행 하나와 그 장의 즐겨찾기 기준.
    private static func kjvState() -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        state.sentenceWithDrawingState = [
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: kjvChapter, verse: 1, sentence: kjvSentence), notebook: .default)
        ]
        state.favoriteChapter = kjvChapter
        return state
    }

    private func makeDetailStore(
        favorites: FavoriteRepositorySpy,
        widget: WidgetVerseClientSpy = WidgetVerseClientSpy(),
        rendered: LockIsolated<[VerseImageContent]> = LockIsolated([])
    ) -> StoreOf<CarveDetailFeature> {
        Store(initialState: Self.kjvState()) {
            CarveDetailFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = favorites
            $0.widgetVerseClient = widget
            $0.photoLibraryClient = AlwaysAddingPhotoLibrary()
            $0.verseImageRenderer = VerseImageRenderer { content in
                rendered.withValue { $0.append(content) }
                return Data("png".utf8)
            }
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.now)
        }
    }

    /// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while true {
            if try await condition() { return }
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: 즐겨찾기 (필사 화면)

    @Test("KJV 장의 별 표시는 KJV 즐겨찾기만 읽는다 — 같은 절의 개역개정 즐겨찾기는 켜지 않는다")
    func chapterMarksReadTranslationOfChapter() async throws {
        let spy = FavoriteRepositorySpy()
        let kjvSecond = FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: Self.kjvChapter, verse: 2), sentence: "", lineData: nil, createdDate: Self.now
        )
        spy.stored.setValue([Self.nkrvFavorite, kjvSecond])
        let store = makeDetailStore(favorites: spy)

        store.send(.reloadFavorites)

        try await waitUntil { store.favoriteVerses == [2] }
        #expect(spy.loadedChapters.value == [Self.kjvChapter])
    }

    @Test("KJV 장에서 즐겨찾기하면 KJV 키로 저장하고, 같은 절의 개역개정 즐겨찾기는 그대로 둔다 — 해제도 KJV 것만 지운다")
    func favoriteToggleUsesTranslationOfChapter() async throws {
        let spy = FavoriteRepositorySpy()
        spy.stored.setValue([Self.nkrvFavorite])
        let store = makeDetailStore(favorites: spy)
        let ink = Data([1, 2, 3])

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: ink)))))
        try await waitUntil { store.favoriteNotice == .added }

        let expected = FavoriteVerseSnapshot(key: Self.kjvKey, sentence: Self.kjvSentence, lineData: ink, createdDate: Self.now)
        #expect(spy.saved.value == [expected])
        #expect(spy.saved.value.map(\.key.translation) == [.KJV])
        #expect(Set(spy.stored.value.map(\.key)) == [Self.nkrvKey, Self.kjvKey])
        #expect(spy.removed.value.isEmpty)

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: ink)))))
        try await waitUntil { spy.removed.value == [Self.kjvKey] }
        #expect(spy.stored.value == [Self.nkrvFavorite])
    }

    // MARK: 위젯에 추가

    @Test("KJV 장에서 위젯에 추가하면 KJV 절을 보관해 담는다 — 위젯 · 즐겨찾기에 있는 같은 절의 개역개정 것을 쓰지 않는다")
    func widgetAddUsesTranslationOfChapter() async throws {
        let favorites = FavoriteRepositorySpy()
        favorites.stored.setValue([Self.nkrvFavorite])
        let widget = WidgetVerseClientSpy()
        widget.current.setValue([Self.nkrvKey])
        let store = makeDetailStore(favorites: favorites, widget: widget)
        let ink = Data([4, 5])

        store.send(.scope(.chapterCanvasAction(.delegate(.widgetRequested(verse: 1, ink: ink)))))
        try await waitUntil { store.widgetNotice == .added(addedToFavorites: true) }

        let expected = FavoriteVerseSnapshot(key: Self.kjvKey, sentence: Self.kjvSentence, lineData: ink, createdDate: Self.now)
        #expect(favorites.saved.value == [expected])
        #expect(widget.added.value == [expected])
        #expect(widget.current.value == [Self.nkrvKey, Self.kjvKey])
        #expect(store.favoriteVerses == [1])
    }

    // MARK: 이미지 저장

    @Test("KJV 장의 절 이미지는 출처에 KJV 약칭을 붙인다 — 권 · 장 · 절 표기는 앱 언어를 따른다")
    func verseImageReferenceUsesTranslationOfChapter() async throws {
        let rendered = LockIsolated<[VerseImageContent]>([])
        let store = makeDetailStore(favorites: FavoriteRepositorySpy(), rendered: rendered)
        let handwriting = VerseImageHandwriting(
            verse: 1, writingSize: CGSize(width: 320, height: 60), underlineAnchors: [30, 60], inkData: nil
        )

        store.send(.scope(.chapterCanvasAction(.delegate(.imageSaveRequested(handwriting)))))
        try await waitUntil { store.imageSaveNotice == .saved }

        // 시험은 ko-KR 로 돈다 — 한국어 기기는 KJV 를 봐도 「시편 23장 1절」 이다(결정 3).
        #expect(rendered.value.map(\.reference) == ["시편 23장 1절 · KJV"])
        #expect(rendered.value.map(\.sentence) == [Self.kjvSentence])
    }

    @Test("이미지 출처는 BibleReference 로 짓는다 — 영어 화면은 「Psalm 23:1 · KJV」, 합쳐진 절은 범위로 적는다")
    func verseImageReferenceFollowsAppLanguage() {
        let english = Locale(identifier: "en")
        let korean = Locale(identifier: "ko")
        #expect(VerseImageContent.reference(chapter: Self.kjvChapter, verse: 1, locale: english) == "Psalm 23:1 · KJV")
        #expect(VerseImageContent.reference(chapter: Self.nkrvChapter, verse: 1, locale: english) == "Psalm 23:1 · NKRV")
        #expect(VerseImageContent.reference(chapter: Self.nkrvChapter, verse: 1, locale: korean) == "시편 23장 1절 · 개역개정")

        let deuteronomy = BibleChapter(title: .deuteronomy, chapter: 6, translation: .BSB)
        #expect(VerseImageContent.reference(chapter: deuteronomy, verse: 18, verseEnd: 19, locale: korean) == "신명기 6장 18-19절 · BSB")
        #expect(VerseImageContent.reference(chapter: deuteronomy, verse: 18, verseEnd: 19, locale: english) == "Deuteronomy 6:18-19 · BSB")
        // 끝 절이 앞 절보다 크지 않으면 절 하나로 적는다.
        #expect(VerseImageContent.reference(chapter: deuteronomy, verse: 18, verseEnd: 18, locale: korean) == "신명기 6장 18절 · BSB")
    }

    // MARK: 즐겨찾기 목록

    @Test("목록은 같은 절의 KJV · 개역개정 즐겨찾기를 따로 보이고, 카드는 번역본 약칭을 적으며, 「말씀으로 이동」 은 그 번역본 장으로 간다")
    func favoriteListKeepsTranslationsApart() async {
        let kjvFavorite = FavoriteVerseSnapshot(key: Self.kjvKey, sentence: Self.kjvSentence, lineData: nil, createdDate: Self.now)
        let store = TestStore(initialState: FavoriteListFeature.State()) {
            FavoriteListFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = FavoriteRepositorySpy()
            $0.continuousClock = TestClock()
        }

        await store.send(.favoritesLoaded(.success([kjvFavorite, Self.nkrvFavorite]))) {
            $0.favorites = [kjvFavorite, Self.nkrvFavorite]
            $0.hasLoaded = true
        }

        // 카드 — 참조는 화면 언어(뷰는 환경 locale 을 넘긴다), 번역본 약칭은 그 아래 줄이다.
        let korean = Locale(identifier: "ko")
        #expect(FavoriteListView.referenceText(Self.kjvKey, locale: korean) == "시편 23장 1절")
        #expect(FavoriteListView.referenceText(Self.kjvKey, locale: Locale(identifier: "en")) == "Psalm 23:1")
        #expect(FavoriteListView.translationText(Self.kjvKey, locale: korean) == "KJV")
        #expect(FavoriteListView.translationText(Self.nkrvKey, locale: korean) == "개역개정")
        #expect(FavoriteListView.translationText(Self.nkrvKey, locale: Locale(identifier: "en")) == "NKRV")

        await store.send(.view(.openVerseTapped(Self.kjvKey)))
        await store.receive(\.delegate.openVerse, BibleVerse(title: Self.kjvChapter, verse: 1, sentence: Self.kjvSentence))
    }

    // MARK: 이전 필사

    /// 저장소에 미리 넣을 시편 23:1 행 하나.
    private struct SeedRow {
        let chapter: BibleChapter
        let key: String
        let ink: Data
        let isPresent: Bool
        let updatedAt: TimeInterval
    }

    /// 앱 스키마의 인메모리 저장소에 시편 23:1 행을 넣는다 — 개역개정 대표 행 하나, KJV 대표 · 보관 행 둘. @Model 은 컨테이너를 연 뒤에 만든다(iOS 17).
    /// 공유 actor 를 깨우지 않도록 자기 컨테이너를 연다.
    private static func makeHistoryDatabase() throws -> (ModelContainer, SwiftDatabaseActor) {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let seeds = [
            SeedRow(chapter: nkrvChapter, key: "nkrv-current", ink: nkrvRowInk, isPresent: true, updatedAt: 300),
            SeedRow(chapter: kjvChapter, key: "kjv-current", ink: kjvCurrentInk, isPresent: true, updatedAt: 200),
            SeedRow(chapter: kjvChapter, key: "kjv-older", ink: kjvOlderInk, isPresent: false, updatedAt: 100)
        ]
        for seed in seeds {
            let row = BibleDrawing(
                page: seed.chapter.inDefaultNotebook, verse: 1, lineData: seed.ink,
                updateDate: Date(timeIntervalSince1970: seed.updatedAt), rowUUID: seed.key
            )
            row.isPresent = seed.isPresent
            context.insert(row)
        }
        try context.save()
        return (container, SwiftDatabaseActor(modelContainer: container))
    }

    /// 그 장 · 절에서 `isPresent` 인 행의 키.
    private static func presentKeys(_ storeActor: SwiftDatabaseActor, chapter: BibleChapter) async throws -> [String] {
        try await storeActor.verseDrawingSnapshots(page: chapter.inDefaultNotebook, verse: 1).filter(\.isPresent).map(\.rowID.raw)
    }

    @Test("이전 필사는 그 장의 번역본 행만 보이고, 회차를 고르면 그 번역본 행의 대표만 바꾼다 — 개역개정 대표는 그대로다")
    func verseHistoryIsPerTranslation() async throws {
        let (container, storeActor) = try Self.makeHistoryDatabase()
        let database = withDependencies { $0.createSwiftDataActor = storeActor } operation: { DrawingDatabase() }
        let store = Store(initialState: VerseDrawingHistoryFeature.State(page: Self.kjvChapter.inDefaultNotebook, verse: 1)) {
            VerseDrawingHistoryFeature()
        } withDependencies: {
            $0.drawingData = database
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(.ownedForTesting)
        }

        store.send(.view(.fetchDrawings))
        try await waitUntil { store.hasLoaded }
        #expect(store.drawings.map(\.rowID.raw) == ["kjv-current", "kjv-older"])

        let older = try #require(store.drawings.first { $0.rowID.raw == "kjv-older" })
        store.send(.view(.selectDrawing(older)))
        try await waitUntil { try await Self.presentKeys(storeActor, chapter: Self.kjvChapter) == ["kjv-older"] }

        #expect(try await Self.presentKeys(storeActor, chapter: Self.nkrvChapter) == ["nkrv-current"])
        withExtendedLifetime(container) {}
    }

    @Test("이전 필사 시트의 식별은 번역본마다 다르다 — 개역개정은 지금과 같다")
    func verseHistoryIdentityIncludesTranslation() {
        let nkrv = VerseDrawingHistoryFeature.State(page: Self.nkrvChapter.inDefaultNotebook, verse: 1)
        let kjv = VerseDrawingHistoryFeature.State(page: Self.kjvChapter.inDefaultNotebook, verse: 1)

        #expect(nkrv.id == "DrewHistory.1-19Psalms.txt.23.1")
        #expect(kjv.id != nkrv.id)
    }
}
