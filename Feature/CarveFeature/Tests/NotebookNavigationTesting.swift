//
//  NotebookNavigationTesting.swift
//  CarveFeatureTest
//
//  2.2 「회차별 필사책」 — 필사 화면 · 탐색이 지금 필사책으로 page 를 연다(설계 docs/notebook-design.md §6-8).
//  필사책 바꾸기(`switchNotebook`) · 필사책과 장 함께 열기(`openPage`) · 번역본 바꾸기 · 탐색 칠하기 · 지운 필사책 · 전체 삭제 뒤의 page 를 본다.
//  `CarveNavigationFeature.State` · `CarveDetailFeature.State` 는 Equatable 이 아니라 실제 Store 로 상태 전이를 본다(번역본 전환 시험과 같다).
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import SwiftData
import Testing

import ComposableArchitecture

// MARK: - 필사 화면 · 탐색 — 필사책 바꾸기 흐름

@Suite("필사책 바꾸기 — 필사 화면 · 탐색이 지금 필사책으로 page 를 연다")
@MainActor
struct NotebookSwitchNavigationTesting {
    private func makeStore(repository: PageStoreRepository, results: [DrawingEditResult] = []) -> StoreOf<CarveNavigationFeature> {
        let initial = CarveNavigationFeature.State.initialState
        initial.$currentTitle.withLock { $0 = NotebookFixture.psalm }
        return Store(initialState: initial) {
            CarveNavigationFeature()
        } withDependencies: {
            $0.bibleTextClient = NotebookSixVerseText()
            $0.drawingRepository = repository
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results))
            $0.favoriteVerseRepository = FavoriteRepositorySpy()
            $0.uuid = .incrementing
            $0.date = .constant(NotebookFixture.now)
            $0.continuousClock = ImmediateClock()
        }
    }

    /// 지금 장의 본문을 읽고 그 page 의 행을 재서, 캔버스가 그 page 로 합성될 때까지 기다린다.
    private func open(_ store: StoreOf<CarveNavigationFeature>, page: NotebookChapter) async throws {
        store.send(.scope(.carveDetailAction(.view(.fetchSentence))))
        try await eventually {
            store.carveDetailState.chapterCanvas.page == page && store.carveDetailState.sentenceWithDrawingState.count == NotebookFixture.verseCount
        }
        store.send(.scope(.carveDetailAction(.view(.layoutHostingChanged(writingWidth: 372)))))
        try await measure(store, page: page)
    }

    /// 그 page 의 행을 재서 캔버스가 합성될 때까지 기다린다.
    private func measure(_ store: StoreOf<CarveNavigationFeature>, page: NotebookChapter) async throws {
        store.send(.scope(.carveDetailAction(.view(.verseGeometryMeasured(NotebookFixture.geometry(page))))))
        try await eventually { store.carveDetailState.chapterCanvas.page == page && store.carveDetailState.chapterCanvas.isComposed }
    }

    @Test("필사책 A 에서 쓴 획이 저장되기 전에 필사책 B 로 바꾸면 그 획은 A 의 page 로 저장되고, 같은 장 · 보던 절을 B 의 page 로 다시 연다")
    func switchNotebookSavesPendingToPreviousPageAndReopens() async throws {
        try await withIsolatedDefaults {
            let repository = PageStoreRepository()
            let store = makeStore(repository: repository, results: [NotebookFixture.createResult("first", rowID: NotebookFixture.rowInFirst)])
            try await open(store, page: NotebookFixture.firstPage)
            // 4절을 보이는 맨 위에 둔다.
            let region = try #require(store.carveDetailState.chapterLayout.layout?.region(verse: 4))
            store.send(.scope(.carveDetailAction(.view(.headerAnimation(0, -region.captureRect.midY)))))
            #expect(store.carveDetailState.viewingVerse == 4)

            // Given: A 에 쓴 획의 저장이 도는 중이다
            repository.holdNextApply()
            let generation = store.carveDetailState.chapterCanvas.renderedRevision
            store.send(.scope(.carveDetailAction(.scope(.chapterCanvasAction(.editEnded(CanvasTestSupport.edit("first", generation: generation)))))))
            try await eventually { repository.isHoldingApply }

            // When: 필사책을 바꾼다
            store.send(.switchNotebook(NotebookFixture.second))

            // Then: 키를 먼저 쓰고, 보던 절을 지킨 채 같은 장을 B 의 page 로 다시 읽는다
            #expect(store.currentNotebook == NotebookFixture.second)
            #expect(store.carveDetailState.scrollTargetVerse == 4)
            #expect(store.carveDetailState.scrollTargetAnchor == .top)
            try await eventually { store.carveDetailState.chapterCanvas.page == NotebookFixture.secondPage }
            #expect(store.carveDetailState.chapterCanvas.pendingMutations[NotebookFixture.rowInFirst]?.page == NotebookFixture.firstPage)
            // 행 ID 에 필사책이 들어 있다 — 같은 장이라도 행을 새로 만들어 다시 잰다.
            let rowIDs = (1...NotebookFixture.verseCount).map { SentencesWithDrawingFeature.State.rowID(page: NotebookFixture.secondPage, verse: $0) }
            #expect(store.carveDetailState.sentenceWithDrawingState.map(\.id) == rowIDs)

            repository.releaseApply()
            try await eventually { store.carveDetailState.chapterCanvas.isFullyPersisted }
            #expect(repository.appliedPages.value == [NotebookFixture.firstPage])
            #expect(repository.storedRowIDs(NotebookFixture.firstPage) == [NotebookFixture.rowInFirst])
            #expect(repository.storedRowIDs(NotebookFixture.secondPage).isEmpty)

            // B 는 빈 종이로 열린다 — A 의 획이 겹치지 않는다.
            try await measure(store, page: NotebookFixture.secondPage)
            #expect(store.carveDetailState.chapterCanvas.loadedDrawings == [])
            #expect(repository.loadedPages.value.last == NotebookFixture.secondPage)
            #expect(repository.legacyCalls.value == 0)

            // 행이 바뀌면 뷰가 스크롤을 낸다(`CarveDetailView` 의 onChange) — 보던 절을 맨 위에.
            store.send(.scope(.carveDetailAction(.scrollToTop)))
            try await eventually { store.carveDetailState.chapterCanvas.scrollRequest?.verse == 4 }
            #expect(store.carveDetailState.chapterCanvas.scrollRequest?.anchor == .top)
        }
    }

    @Test("책장이 키를 먼저 써도(만들기 · 지우기) 화면이 앞 필사책이면 다시 열고, 이미 그 필사책을 열고 있으면 다시 읽지 않는다")
    func switchNotebookFollowsOpenPageNotKey() async throws {
        try await withIsolatedDefaults {
            let repository = PageStoreRepository()
            let store = makeStore(repository: repository)
            try await open(store, page: NotebookFixture.firstPage)

            // 책장의 「새 필사책」 — 키를 새 필사책으로 쓴 뒤 고름을 알린다(코디네이터 → `switchNotebook`).
            store.withState { $0.$currentNotebookID }.withLock { $0 = NotebookFixture.second.rawValue }
            store.send(.switchNotebook(NotebookFixture.second))
            try await eventually { store.carveDetailState.chapterCanvas.page == NotebookFixture.secondPage }
            try await eventually { repository.loadedPages.value.last == NotebookFixture.secondPage }

            // 같은 필사책을 다시 골라도 다시 읽지 않는다 — 같은 page 를 다시 읽으면 행이 그대로라 다시 재지 않는다.
            let loads = repository.loadedPages.value.count
            store.send(.switchNotebook(NotebookFixture.second))
            try await Task.sleep(for: .milliseconds(100))
            #expect(repository.loadedPages.value.count == loads)
            #expect(store.carveDetailState.chapterCanvas.page == NotebookFixture.secondPage)
        }
    }

    @Test("번역본을 바꿔도 필사책은 그대로다 — 같은 필사책의 그 번역본 page 를 연다")
    func translationSwitchKeepsCurrentNotebook() async throws {
        try await withIsolatedDefaults {
            let repository = PageStoreRepository()
            let store = makeStore(repository: repository)
            try await open(store, page: NotebookFixture.firstPage)
            store.send(.switchNotebook(NotebookFixture.second))
            try await eventually { store.carveDetailState.chapterCanvas.page == NotebookFixture.secondPage }

            store.send(.scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(.KJV)))))))

            let kjvPage = NotebookChapter(notebook: NotebookFixture.second, chapter: NotebookFixture.psalmKJV)
            try await eventually { store.carveDetailState.chapterCanvas.page == kjvPage }
            try await eventually { repository.loadedPages.value.last == kjvPage }
            #expect(store.currentNotebook == NotebookFixture.second)
            #expect(store.currentTitle == NotebookFixture.psalmKJV)
        }
    }

    @Test("필사책과 장을 함께 열면 그 필사책의 page 로 그 장을 연다 — 차트의 최근 기록")
    func openPageOpensChapterInItsNotebook() async throws {
        try await withIsolatedDefaults {
            let repository = PageStoreRepository()
            let store = makeStore(repository: repository)
            try await open(store, page: NotebookFixture.firstPage)
            let john = BibleChapter(title: .john, chapter: 3, translation: .KJV)
            let page = NotebookChapter(notebook: NotebookFixture.second, chapter: john)

            store.send(.openPage(page, verse: 5))

            try await eventually { store.carveDetailState.chapterCanvas.page == page }
            #expect(store.currentNotebook == NotebookFixture.second)
            #expect(store.currentTitle == john)
            #expect(store.carveDetailState.scrollTargetVerse == 5)
            try await eventually { repository.loadedPages.value.last == page }
        }
    }

    @Test("필사책을 바꾸면 탐색이 칠한 장을 비우고, 열린 탐색은 그 필사책의 기록으로 다시 칠한다")
    func switchNotebookRepaintsDrawnChapters() async throws {
        try await withIsolatedDefaults {
            let (container, storeActor) = try NotebookFixture.makeDatabase([
                .init(page: BibleChapter(title: .psalms, chapter: 3).inDefaultNotebook, key: "first-3", seed: 1, updatedAt: 100),
                .init(page: NotebookChapter(notebook: NotebookFixture.second, chapter: BibleChapter(title: .psalms, chapter: 5)),
                      key: "second-5", seed: 2, updatedAt: 200)
            ])
            let database = withDependencies { $0.createSwiftDataActor = storeActor } operation: { DrawingDatabase() }
            var initial = CarveNavigationFeature.State.initialState
            initial.$currentTitle.withLock { $0 = NotebookFixture.psalm }
            initial.columnVisibility = .all
            initial.selectedTitle = .psalms
            initial.selectedChapter = 23
            initial.drawnChapters = [.psalms: [3]]
            let store = Store(initialState: initial) {
                CarveNavigationFeature()
            } withDependencies: {
                $0.drawingData = database
                $0.bibleTextClient = NotebookUnreadableText()
                $0.drawingRepository = PageStoreRepository()
            }

            store.send(.switchNotebook(NotebookFixture.second))
            #expect(store.drawnChapters[.psalms] != [3])
            try await eventually { store.drawnChapters[.psalms] == [5] }
            // 탐색 선택은 그대로다.
            #expect(store.columnVisibility == .all)
            #expect(store.selectedChapter == 23)

            store.send(.switchNotebook(.default))
            try await eventually { store.drawnChapters[.psalms] == [3] }
            withExtendedLifetime(container) {}
        }
    }
}

// MARK: - 지금 필사책이 목록에 없을 때 · 전체 삭제

@Suite("필사책 바꾸기 — 지운 필사책 · 전체 삭제 뒤에는 기본 필사책으로 연다")
@MainActor
struct NotebookFallbackTesting {
    private func makeLaunchStore(notebooks: NotebookListStub, arrivals: ControlledArrivals, current: NotebookID) -> StoreOf<CarveNavigationFeature> {
        let initial = CarveNavigationFeature.State.initialState
        initial.$currentNotebookID.withLock { $0 = current.rawValue }
        return Store(initialState: initial) {
            CarveNavigationFeature()
        } withDependencies: {
            $0.notebookRepository = notebooks
            $0.cloudImportArrivals = arrivals
            $0.bibleTextClient = NotebookUnreadableText()
            $0.drawingRepository = PageStoreRepository()
        }
    }

    @Test("지금 필사책이 목록에 없으면(다른 기기에서 지움) 시작 때 기본 필사책으로 돌아간다 — 다시 나타나도 목록을 다시 읽지 않는다")
    func deletedCurrentNotebookFallsBackAtStart() async throws {
        try await withIsolatedDefaults {
            let notebooks = NotebookListStub()
            notebooks.listed.setValue([.default, NotebookFixture.third])
            let arrivals = ControlledArrivals()
            let store = makeLaunchStore(notebooks: notebooks, arrivals: arrivals, current: NotebookFixture.second)
            #expect(store.currentNotebook == NotebookFixture.second)

            store.send(.scope(.carveDetailAction(.view(.appeared))))
            try await eventually { store.currentNotebook == .default }
            #expect(notebooks.reads.value == 1)

            // 사이드바를 닫으면 필사 화면이 다시 나타난다 — 시작 확인은 한 번뿐이다.
            store.send(.scope(.carveDetailAction(.view(.appeared))))
            try await Task.sleep(for: .milliseconds(100))
            #expect(notebooks.reads.value == 1)
            arrivals.finish()
        }
    }

    @Test("iCloud 에서 받은 것이 들어올 때 지금 필사책이 목록에서 사라졌으면 기본 필사책으로 돌아간다 — 목록에 있으면 그대로다")
    func deletedCurrentNotebookFallsBackOnArrival() async throws {
        try await withIsolatedDefaults {
            let notebooks = NotebookListStub()
            notebooks.listed.setValue([.default, NotebookFixture.second])
            let arrivals = ControlledArrivals()
            let store = makeLaunchStore(notebooks: notebooks, arrivals: arrivals, current: NotebookFixture.second)

            store.send(.scope(.carveDetailAction(.view(.appeared))))
            try await eventually { notebooks.reads.value == 1 && arrivals.subscriberCount == 1 }
            #expect(store.currentNotebook == NotebookFixture.second)

            // 다른 기기가 그 필사책을 지웠고, 그 변경이 iCloud 로 들어왔다.
            notebooks.listed.setValue([.default])
            arrivals.arrive(at: 2_000)
            try await eventually { store.currentNotebook == .default }
            #expect(notebooks.reads.value == 2)
            arrivals.finish()
        }
    }

    @Test("목록을 보는 사이 지금 필사책이 바뀌었으면(책장에서 고름) 그 결과로 기본 필사책으로 돌리지 않는다")
    func staleCheckResultIsIgnored() async throws {
        try await withIsolatedDefaults {
            var state = CarveNavigationFeature.State.initialState
            state.$currentNotebookID.withLock { $0 = NotebookFixture.third.rawValue }
            let reducer = CarveNavigationFeature()

            _ = reducer.reduce(into: &state, action: .currentNotebookChecked(NotebookFixture.second, isListed: false))
            #expect(state.currentNotebook == NotebookFixture.third)
            _ = reducer.reduce(into: &state, action: .currentNotebookChecked(NotebookFixture.third, isListed: true))
            #expect(state.currentNotebook == NotebookFixture.third)
            _ = reducer.reduce(into: &state, action: .currentNotebookChecked(NotebookFixture.third, isListed: false))
            #expect(state.currentNotebook == .default)
        }
    }

    @Test("전체 삭제로 지금 필사책 키가 기본으로 돌아간 뒤 세대가 오르면, 지운 필사책이 아니라 기본 필사책 page 로 다시 읽고 그 뒤 필기도 기본 page 에 저장한다")
    func dataClearReopensInCurrentNotebook() async throws {
        try await withIsolatedDefaults {
            let repository = PageStoreRepository()
            let initial = CarveDetailFeature.State.initialState
            initial.headerState.$currentTitle.withLock { $0 = NotebookFixture.psalm }
            initial.$currentNotebookID.withLock { $0 = NotebookFixture.second.rawValue }
            let store = Store(initialState: initial) {
                CarveDetailFeature()
            } withDependencies: {
                $0.bibleTextClient = NotebookSixVerseText()
                $0.drawingRepository = repository
                $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([
                    NotebookFixture.createResult("second", rowID: NotebookFixture.rowInSecond),
                    NotebookFixture.createResult("first", rowID: NotebookFixture.rowInFirst)
                ]))
                $0.favoriteVerseRepository = FavoriteRepositorySpy()
                $0.uuid = .incrementing
                $0.date = .constant(NotebookFixture.now)
                $0.continuousClock = ImmediateClock()
            }

            // Given: 두 번째 필사책의 시편 23편에 쓰고 저장했다
            store.send(.view(.fetchSentence))
            try await eventually { store.chapterCanvas.page == NotebookFixture.secondPage && store.sentenceWithDrawingState.count == NotebookFixture.verseCount }
            store.send(.view(.layoutHostingChanged(writingWidth: 372)))
            store.send(.view(.verseGeometryMeasured(NotebookFixture.geometry(NotebookFixture.secondPage))))
            try await eventually { store.chapterCanvas.isComposed }
            store.send(.scope(.chapterCanvasAction(.editEnded(CanvasTestSupport.edit("second", generation: store.chapterCanvas.renderedRevision)))))
            try await eventually { repository.appliedPages.value == [NotebookFixture.secondPage] && store.chapterCanvas.isFullyPersisted }

            // When: 설정의 「모든 필사 데이터 삭제」 — 지금 필사책 키를 기본으로 돌린 뒤 세대를 올린다(설정 화면의 순서)
            store.withState { $0.$currentNotebookID }.withLock { $0 = NotebookID.default.rawValue }
            store.withState { $0.$drawingDataRevision }.withLock { $0 += 1 }
            store.send(.view(.drawingDataRevisionChanged))

            // Then: 지운 필사책이 아니라 기본 필사책 page 를 연다 — 행도 기본 필사책으로 새로 만든다
            try await eventually { store.chapterCanvas.page == NotebookFixture.firstPage }
            #expect(store.sentenceWithDrawingState.first?.id == SentencesWithDrawingFeature.State.rowID(page: NotebookFixture.firstPage, verse: 1))
            try await eventually { repository.loadedPages.value.contains(NotebookFixture.firstPage) }
            store.send(.view(.verseGeometryMeasured(NotebookFixture.geometry(NotebookFixture.firstPage))))
            try await eventually { store.chapterCanvas.isComposed }
            #expect(store.chapterCanvas.page == NotebookFixture.firstPage)

            // 그 뒤 필기는 기본 필사책 page 로 저장된다 — 지운 필사책의 접두 행이 생기지 않는다.
            store.send(.scope(.chapterCanvasAction(.editEnded(CanvasTestSupport.edit("first", generation: store.chapterCanvas.renderedRevision)))))
            try await eventually { repository.appliedPages.value.count == 2 && store.chapterCanvas.isFullyPersisted }
            #expect(repository.appliedPages.value == [NotebookFixture.secondPage, NotebookFixture.firstPage])
            #expect(repository.storedRowIDs(NotebookFixture.firstPage) == [NotebookFixture.rowInFirst])
            #expect(repository.legacyCalls.value == 0)
        }
    }
}
