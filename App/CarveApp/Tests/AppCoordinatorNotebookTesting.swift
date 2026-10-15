//
//  AppCoordinatorNotebookTesting.swift
//  CarveAppTest
//
//  책장 · 필사책(2.2 회차별 필사책)의 화면 경계 — 필사 화면의 「책장」 이 책장을 쌓고, 책장의 위임이 path 와 필사 화면의 지금 필사책을 바꾼다.
//  차트의 최근 장 · 절은 지금 필사책이 아니라 그 기록의 필사책으로 연다(`openPage`). 필사 화면이 장을 여는 과정은 CarveFeature 시험이 본다.
//

import CarveFeature
import ChartFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 책장 · 필사책")
@MainActor
struct AppCoordinatorNotebookTesting {
    /// 기본이 아닌 필사책 — 두 번째로 만든 필사책.
    private static let secondNotebook = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000002")!)

    /// 요한복음 3장(KJV) — 번역본도 함께 나르는지 본다.
    private static let johnKJV = BibleChapter(title: .john, chapter: 3, translation: .KJV)

    /// 필사 화면에 그 필사책을 지금 필사책으로 하라고 보냈는가.
    private static func isSwitchNotebook(_ notebook: NotebookID) -> (AppCoordinatorFeature.Action) -> Bool {
        { action in
            guard case .root(.presented(.carve(.switchNotebook(let received)))) = action else { return false }
            return received == notebook
        }
    }

    /// 필사 화면에 그 필사책 · 장(· 절)을 열라고 보냈는가. 값이 튜플이라 꺼내어 견준다.
    private static func isOpenPage(_ page: NotebookChapter, verse: Int?) -> (AppCoordinatorFeature.Action) -> Bool {
        { action in
            guard case .root(.presented(.carve(.openPage(let receivedPage, let receivedVerse)))) = action else { return false }
            return receivedPage == page && receivedVerse == verse
        }
    }

    // MARK: 책장 열기 · 닫기

    @Test("필사 화면의 「책장」 은 책장을 필사 화면 위에 쌓고 화면 키를 Notebooks 로 한다")
    func moveToNotebooksPushesShelf() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())

        await store.send(.root(.presented(.carve(.view(.moveToNotebooks)))))

        #expect(store.state.pathScreens == [.notebooks])
        #expect(store.state.currentScreenKey == "Notebooks")
        await store.finish()
    }

    @Test("책장의 뒤로 버튼은 책장만 닫는다 — 필사 화면은 그대로다")
    func shelfBackTappedPopsShelf() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.notebooks(.initialState)]))
        let shelfID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: shelfID, action: .notebooks(.view(.backTapped)))))
        await store.receive(\.path)

        #expect(store.state.pathScreens.isEmpty)
        #expect(store.state.rootScreen == .carve)
        #expect(store.state.carve?.currentNotebook == .default)
        await store.finish()
    }

    // MARK: 필사책 바꾸기

    @Test("책장에서 필사책을 고르면 쌓인 화면을 모두 닫고 필사 화면의 지금 필사책을 바꾼다")
    func notebookChosenClearsPathAndSwitchesNotebook() async throws {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState), .notebooks(.initialState)]))
        let shelfID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: shelfID, action: .notebooks(.delegate(.notebookChosen(Self.secondNotebook))))))
        #expect(store.state.pathScreens.isEmpty)

        await store.receive(Self.isSwitchNotebook(Self.secondNotebook))
        #expect(store.state.carve?.currentNotebook == Self.secondNotebook)
        #expect(store.state.carve?.currentNotebookID == Self.secondNotebook.rawValue)
        await store.finish()
    }

    @Test("책장에 머문 채 지금 필사책이 바뀌면 책장은 그대로 두고 뒤의 필사 화면만 바꾼다")
    func currentNotebookChangedKeepsShelf() async throws {
        // Given: 두 번째 필사책을 쓰던 중 책장을 열었다
        let store = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
            var state = CoordinatorFixture.writing(path: [.notebooks(.initialState)])
            if case .carve(var carve)? = state.root {
                carve.$currentNotebookID.withLock { $0 = Self.secondNotebook.rawValue }
                state.root = .carve(carve)
            }
            return state
        }())
        #expect(store.state.carve?.currentNotebook == Self.secondNotebook)
        let shelfID = try #require(store.state.path.ids.last)

        // When: 지금 필사책을 지워 기본 필사책으로 돌아간다
        await store.send(.path(.element(id: shelfID, action: .notebooks(.delegate(.currentNotebookChanged(.default))))))

        // Then: 책장은 남고, 필사 화면은 기본 필사책이다
        await store.receive(Self.isSwitchNotebook(.default))
        #expect(store.state.pathScreens == [.notebooks])
        #expect(store.state.carve?.currentNotebook == .default)
        await store.finish()
    }

    // MARK: 차트의 최근 기록 — 그 필사책으로 연다

    @Test("차트에서 다른 필사책의 최근 절을 고르면 차트를 닫고 그 필사책 · 장의 그 절로 간다")
    func chartRecentVerseOpensPageInItsNotebook() async throws {
        let page = NotebookChapter(notebook: Self.secondNotebook, chapter: Self.johnKJV)
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState)]))
        let chartID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: chartID, action: .chart(.drawingWeeklySummary(.openVerse(page, verse: 16))))))
        #expect(store.state.pathScreens.isEmpty)

        // 필사 화면은 필사책을 바꾼 뒤 장 이동과 같은 길로 그 절을 연다 — 번역본도 기록 그대로다.
        await store.receive(Self.isOpenPage(page, verse: 16))
        #expect(store.state.carve?.currentNotebook == Self.secondNotebook)
        await store.receive(\.root.presented.carve.moveToVerse, BibleVerse(title: Self.johnKJV, verse: 16, sentence: ""))
        #expect(store.state.carve?.currentTitle == Self.johnKJV)
        await store.finish()
    }

    @Test("차트에서 최근 장을 고르면 차트를 닫고 그 필사책의 장으로 간다")
    func chartRecentChapterOpensPageInItsNotebook() async throws {
        let page = NotebookChapter(notebook: .default, chapter: BibleChapter(title: .psalms, chapter: 119))
        let store = makeCoordinatorStore(CoordinatorFixture.writing(path: [.chart(.initialState)]))
        let chartID = try #require(store.state.path.ids.last)

        await store.send(.path(.element(id: chartID, action: .chart(.drawingWeeklySummary(.openChapter(page))))))
        #expect(store.state.pathScreens.isEmpty)

        await store.receive(Self.isOpenPage(page, verse: nil))
        #expect(store.state.carve?.currentNotebook == .default)
        await store.receive(\.root.presented.carve.moveToChapter, page.chapter)
        await store.finish()
    }
}
