//
//  SyncedWriteGateTesting.swift
//  CarveFeatureTest
//
//  동기화 저장소에 바로 쓰는 경로는 **쓰기 진입점에서** 막는다 (정책 §12-6 결정 1, ACC-1 F30).
//

import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 메뉴 · 버튼만 감추고 실제 쓰기는 그대로 나가는 것 — 소유가 확인되지 않은 세션의 즐겨찾기 · 위젯 보관 · 목록 되돌리기 · N-Canvas 저장 ·
///   기록 복원이 동기화 저장소에 들어가면 다음에 확인되는 계정으로 올라간다(F30)
/// - 막았는데 화면 표시(별 · 목록 · 배지)는 바뀐 채로 남는 것
@Suite("동기화 쓰기 게이트 — 쓰기 진입점에서 막는다")
@MainActor
struct SyncedWriteGateTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let sentence = "여호와는 나의 목자시니 내가 부족함이 없으리로다"
    private static let now = Date(timeIntervalSince1970: 1_000)

    /// 로그인하지 않은 환경 — 쓰면 다음에 로그인한 계정으로 올라간다(F30).
    private static let signedOutEnvironment = DrawingEditEnvironment(
        accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge()
    )
    private static var signedOut: any DrawingEditEnvironmentClient { StubDrawingEditEnvironment(signedOutEnvironment) }

    private static let listFavorite = FavoriteVerseSnapshot(
        key: FavoriteVerseKey(chapter: chapter, verse: 1), sentence: sentence, lineData: nil,
        createdDate: Date(timeIntervalSince1970: 200)
    )

    private func makeListStore(
        spy: FavoriteRepositorySpy,
        environment: ControlledEditEnvironment,
        favorites: [FavoriteVerseSnapshot]
    ) -> TestStoreOf<FavoriteListFeature> {
        var state = FavoriteListFeature.State()
        state.favorites = IdentifiedArray(uniqueElements: favorites)
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FavoriteListFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = spy
            $0.drawingEditEnvironment = environment
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private static func detailState(favorites: Set<Int> = []) -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        state.sentenceWithDrawingState = [
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: chapter, verse: 1, sentence: sentence), drawing: nil)
        ]
        state.favoriteChapter = chapter
        state.favoriteVerses = favorites
        return state
    }

    private func makeDetailStore(
        favorites: FavoriteRepositorySpy,
        widget: WidgetVerseClientSpy = WidgetVerseClientSpy(),
        clock: TestClock<Duration> = TestClock(),
        favoriteVerses: Set<Int> = []
    ) -> StoreOf<CarveDetailFeature> {
        Store(initialState: Self.detailState(favorites: favoriteVerses)) {
            CarveDetailFeature()
        } withDependencies: {
            $0.favoriteVerseRepository = favorites
            $0.widgetVerseClient = widget
            $0.drawingEditEnvironment = Self.signedOut
            $0.continuousClock = clock
            $0.date = .constant(Self.now)
            $0.drawingRepository = RepositorySpy()
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.uuid = .incrementing
            $0.undoManager = SharedUndoManager()
        }
    }

    /// 획이 있는 필기 데이터 — 기록 목록은 획 없는 행을 거른다(`historyRows`).
    private static func ink(x offset: Double) -> Data {
        let points = (0..<8).map { index in
            PKStrokePoint(
                location: CGPoint(x: offset + Double(index) * 10, y: 0), timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
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

    // MARK: - 필사 화면의 즐겨찾기 · 위젯

    @Test("소유가 확인되지 않으면 즐겨찾기를 저장하지 않고, 켜 둔 별을 되돌리며 사유를 보인다")
    func favoriteAddIsBlockedAtWrite() async throws {
        let favorites = FavoriteRepositorySpy()
        let store = makeDetailStore(favorites: favorites)

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: Data([1]))))))
        #expect(store.favoriteVerses == [1])

        try await waitUntil { store.favoriteNotice != nil }
        let expected = FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: Self.chapter, verse: 1), sentence: Self.sentence, lineData: Data([1]), createdDate: Self.now
        )
        #expect(store.favoriteNotice == .blocked(.add(expected), .signedOut))
        #expect(store.favoriteVerses.isEmpty)
        #expect(favorites.saved.value.isEmpty)
    }

    @Test("소유가 확인되지 않으면 즐겨찾기 해제도 하지 않고 별을 되돌린다")
    func favoriteRemoveIsBlockedAtWrite() async throws {
        let favorites = FavoriteRepositorySpy()
        let store = makeDetailStore(favorites: favorites, favoriteVerses: [1])

        store.send(.scope(.chapterCanvasAction(.delegate(.favoriteToggled(verse: 1, ink: Data([1]))))))
        #expect(store.favoriteVerses.isEmpty)

        try await waitUntil { store.favoriteNotice != nil }
        #expect(store.favoriteVerses == [1])
        #expect(favorites.removed.value.isEmpty)
    }

    @Test("소유가 확인되지 않으면 위젯에 담으려고 보관하지 않는다 — 위젯에도 담기지 않는다")
    func widgetArchiveIsBlockedAtWrite() async throws {
        let favorites = FavoriteRepositorySpy()
        let widget = WidgetVerseClientSpy()
        let store = makeDetailStore(favorites: favorites, widget: widget)

        store.send(.scope(.chapterCanvasAction(.delegate(.widgetRequested(verse: 1, ink: Data([1]))))))

        try await waitUntil { store.widgetNotice != nil }
        #expect(store.widgetNotice == .blocked(.signedOut))
        #expect(favorites.saved.value.isEmpty)
        #expect(widget.added.value.isEmpty)
        #expect(store.favoriteVerses.isEmpty)
    }

    @Test("N-Canvas 는 확인되기 전에는 입력을 닫고 사유를 든다")
    func nCanvasInputIsClosedUntilConfirmed() {
        var state = Self.detailState()
        // 처음에는 확인 전으로 막아 둔다 — 열어 두고 뒤늦게 막으면 그 사이 쓴 필기가 저장소에 들어간다.
        #expect(state.nCanvasWriteBlock == .accountUnconfirmed)

        _ = CarveDetailFeature().reduce(into: &state, action: .syncedWriteGateChanged(.signedOut))
        #expect(state.nCanvasWriteBlock == .signedOut)

        _ = CarveDetailFeature().reduce(into: &state, action: .syncedWriteGateChanged(nil))
        #expect(state.nCanvasWriteBlock == nil)
    }

    @Test("N-Canvas 의 저장은 쓰기 직전에 막는다 — 막히면 저장소에 행이 생기지 않는다")
    func nCanvasSaveIsBlockedAtWrite() async throws {
        let chapter = BibleChapter(title: .nahum, chapter: 3)
        let request = LegacyDrawingSaveRequest(
            chapter: chapter, verse: 42, rowID: BibleDrawingRowID(raw: UUID().uuidString), lineData: Data([7]),
            updateDate: Self.now, drawingVersion: 2, layoutMetadataData: nil
        )

        try await withDependencies {
            $0.drawingEditEnvironment = Self.signedOut
            $0.createSwiftDataActor = .testValue
        } operation: {
            try await CarveDetailFeature().persistDrawing(request)
            @Dependency(\.drawingData) var drawingData
            #expect(try await drawingData.fetchDrawings(chapter: chapter, verse: 42).isEmpty)
        }

        // 소유가 확인된 환경에서는 같은 요청이 저장된다 — 게이트가 저장 자체를 막는 것이 맞는지 함께 본다.
        try await withDependencies {
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(.ownedForTesting)
            $0.createSwiftDataActor = .testValue
        } operation: {
            try await CarveDetailFeature().persistDrawing(request)
            @Dependency(\.drawingData) var drawingData
            #expect(try await drawingData.fetchDrawings(chapter: chapter, verse: 42).count == 1)
        }
    }

    // MARK: - 즐겨찾기 목록

    @Test("소유가 확인되지 않으면 목록의 해제를 쓰지 않고 목록을 되돌린다")
    func favoriteListRemoveIsBlocked() async throws {
        let spy = FavoriteRepositorySpy()
        let favorite = Self.listFavorite
        let store = makeListStore(spy: spy, environment: ControlledEditEnvironment(Self.signedOutEnvironment), favorites: [favorite])

        await store.send(.view(.unfavoriteTapped(favorite.key)))
        await store.receive(\.writeBlocked)

        #expect(store.state.favorites == [favorite])
        #expect(store.state.notice == .blocked(.signedOut))
        #expect(spy.removed.value.isEmpty)
        await store.finish()
    }

    /// 해제한 뒤 계정이 바뀌면 되돌리기도 막힌다 — 되돌린 목록을 다시 내린다.
    @Test("해제 뒤 소유가 확인되지 않게 되면 「실행 취소」 도 쓰지 않고 목록을 되돌린다")
    func favoriteListRestoreIsBlocked() async throws {
        let spy = FavoriteRepositorySpy()
        let favorite = Self.listFavorite
        let environment = ControlledEditEnvironment(.ownedForTesting)
        let store = makeListStore(spy: spy, environment: environment, favorites: [favorite])

        await store.send(.view(.unfavoriteTapped(favorite.key)))
        await store.receive(\.removeFinished)
        #expect(spy.removed.value == [favorite.key])

        environment.change(to: Self.signedOutEnvironment)
        await store.send(.view(.noticeActionTapped))
        await store.receive(\.writeBlocked)

        #expect(store.state.favorites.isEmpty)
        #expect(store.state.notice == .blocked(.signedOut))
        #expect(spy.saved.value.isEmpty)
        await store.finish()
    }

    // MARK: - 이전 필사 기록 복원

    @Test("소유가 확인되지 않으면 회차를 바꾸지 않고 사유를 보인다 — 화면의 회차 표시도 그대로다")
    func historyRestoreIsBlockedAtWrite() async throws {
        let container = try ModelContainer(
            for: BibleDrawing.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let present = BibleDrawing(bibleTitle: Self.chapter, verse: 1, lineData: Self.ink(x: 0), updateDate: Self.now)
        present.isPresent = true
        let older = BibleDrawing(bibleTitle: Self.chapter, verse: 1, lineData: Self.ink(x: 40),
                                 updateDate: Date(timeIntervalSince1970: 500))
        older.isPresent = false
        context.insert(present)
        context.insert(older)
        try context.save()

        // `State` 가 Equatable 이 아니라 실제 Store 로 본다.
        let store = Store(initialState: VerseDrawingHistoryFeature.State(title: Self.chapter, verse: 1)) {
            VerseDrawingHistoryFeature()
        } withDependencies: {
            $0.drawingEditEnvironment = Self.signedOut
        }
        store.send(.setDrawings([present, older]))
        store.send(.view(.selectDrawing(older)))

        try await waitUntil { store.restoreBlock != nil }
        #expect(store.restoreBlock == .signedOut)
        #expect(VerseDrawingHistoryView.blockedMessage(.signedOut).hasPrefix("이 회차로 바꾸지 않았어요"))
        // 지금 보이는 회차는 그대로다 — 목록 표시도 바꾸지 않았다.
        #expect(store.drawings.first { $0.isPresent == true } === present)
    }
}
