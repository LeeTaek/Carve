//
//  NotebookSwitchTesting.swift
//  CarveFeatureTest
//
//  2.2 「회차별 필사책」 — 필사 화면의 저장 경로가 page(필사책 + 장)를 나른다(설계 docs/notebook-design.md §6-8 · §7).
//  필사책 바꾸기는 장 바꾸기와 같은 흐름이다: 앞 필사책의 대기 명령 · 지우기 작업은 앞 page 를 들고 있어 앞 필사책으로 저장되고, 새 page 를 읽는다.
//  저장 큐 · 세대 · 합성 규칙은 그대로이고 장 식별만 page 로 넓혔다 — 이 파일은 필사책끼리 섞이지 않는 것을 고정한다.
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import SwiftData
import SwiftUI
import Testing

import ComposableArchitecture

// MARK: - 캔버스 — 저장 경로가 page 를 나른다

@Suite("필사책 바꾸기 — 캔버스의 대기 명령 · 지우기 · 도착 반영은 page 를 든다")
@MainActor
struct NotebookSwitchCanvasTesting {
    private func makeStore(
        _ repository: PageStoreRepository,
        page: NotebookChapter,
        results: [DrawingEditResult] = [],
        composeInputs: LockIsolated<[[VerseDrawingSnapshot]]>? = nil
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: ChapterCanvasFeature.State(page: page)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results), composeInputs: composeInputs)
            $0.drawingRepository = repository
            $0.uuid = .incrementing
            $0.date = .constant(NotebookFixture.now)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    /// page 를 열고 합성한다.
    private func compose(_ store: TestStoreOf<ChapterCanvasFeature>, _ page: NotebookChapter) async {
        await store.send(.load(page: page, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
    }

    /// 효과가 모두 끝난 뒤 받은 액션까지 반영한다 — 도착 순서를 시험이 정하지 않는 흐름용.
    private func settle(_ store: TestStoreOf<ChapterCanvasFeature>) async {
        await store.finish()
        await store.skipReceivedActions(strict: false)
    }

    @Test("필사책 A 에서 쓴 획이 저장되기 전에 같은 장의 필사책 B 로 바꾸면, 그 획은 A 의 행으로 저장되고 B 는 빈 종이로 열린다")
    func pendingStrokeIsSavedToItsNotebook() async throws {
        let repository = PageStoreRepository()
        let inputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = makeStore(
            repository, page: NotebookFixture.firstPage,
            results: [NotebookFixture.createResult("first", rowID: NotebookFixture.rowInFirst)], composeInputs: inputs
        )
        await compose(store, NotebookFixture.firstPage)

        // Given: A 에 쓴 획의 저장이 도는 중이다
        repository.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("first")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.inFlightPage == NotebookFixture.firstPage)

        // When: 저장이 끝나기 전에 필사책을 바꾼다 — 같은 장 · 다른 필사책
        await store.send(.load(page: NotebookFixture.secondPage, expectedVerseCount: 3))
        #expect(store.state.page == NotebookFixture.secondPage)
        #expect(store.state.pendingMutations[NotebookFixture.rowInFirst]?.page == NotebookFixture.firstPage)
        try await eventually { repository.isHoldingApply }
        repository.releaseApply()
        await settle(store)

        // Then: 획은 A 의 행으로만 저장됐고, B 의 내용(loadedDrawings)에도 겹쳐지지 않았다
        #expect(repository.appliedPages.value == [NotebookFixture.firstPage])
        #expect(repository.storedRowIDs(NotebookFixture.firstPage) == [NotebookFixture.rowInFirst])
        #expect(repository.storedRowIDs(NotebookFixture.secondPage).isEmpty)
        #expect(repository.loadedPages.value == [NotebookFixture.firstPage, NotebookFixture.secondPage])
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.loadedDrawings == [])

        // B 는 빈 종이로 합성된다.
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(store.state.isComposed)
        #expect(inputs.value.last == [])
        #expect(repository.legacyCalls.value == 0)
    }

    @Test("저장에 실패한 A 의 획은 B 로 바꾼 뒤에도 A 의 것으로 남고 B 에 겹쳐 보이지 않는다 — 다시 시도하면 A 로 저장된다")
    func failedStrokeStaysWithItsNotebook() async {
        let repository = PageStoreRepository()
        repository.applyFailures.setValue(2)
        let inputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = makeStore(
            repository, page: NotebookFixture.firstPage,
            results: [NotebookFixture.createResult("first", rowID: NotebookFixture.rowInFirst)], composeInputs: inputs
        )
        await compose(store, NotebookFixture.firstPage)
        await store.send(.editEnded(CanvasTestSupport.edit("first")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)   // 실패 1 — 큐 보존
        #expect(store.state.saveRetryCount == 1)

        // 필사책을 바꾼다 — 전환 flush 가 A 로 다시 시도하고(실패 2), B 를 읽는다.
        await store.send(.load(page: NotebookFixture.secondPage, expectedVerseCount: 3))
        await settle(store)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))

        // B 의 합성 입력 · 지금 필기에 A 의 미저장 획이 없다. 미저장분은 여전히 A 의 것이다.
        #expect(store.state.isComposed)
        #expect(inputs.value.last == [])
        #expect(ChapterCanvasFeature.currentInk(verse: 2, state: store.state) == nil)
        #expect(store.state.pendingMutations[NotebookFixture.rowInFirst]?.page == NotebookFixture.firstPage)

        // 「다시 시도」 — B 를 보는 중이어도 A 로 저장된다.
        await store.send(.flushPending)
        await settle(store)
        #expect(repository.appliedPages.value == Array(repeating: NotebookFixture.firstPage, count: 3))
        #expect(repository.storedRowIDs(NotebookFixture.firstPage) == [NotebookFixture.rowInFirst])
        #expect(repository.storedRowIDs(NotebookFixture.secondPage).isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.loadedDrawings == [])
    }

    @Test("A → B → A 로 돌아오면 A 의 필기가 보이고, B 에 쓴 필기는 B 에만 있다")
    func returningToNotebookShowsItsOwnInk() async {
        let repository = PageStoreRepository()
        let store = makeStore(repository, page: NotebookFixture.firstPage, results: [
            NotebookFixture.createResult("first", rowID: NotebookFixture.rowInFirst),
            NotebookFixture.createResult("second", rowID: NotebookFixture.rowInSecond)
        ])
        await compose(store, NotebookFixture.firstPage)
        await store.send(.editEnded(CanvasTestSupport.edit("first")))
        await settle(store)

        await store.send(.load(page: NotebookFixture.secondPage, expectedVerseCount: 3))
        await settle(store)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(store.state.loadedDrawings == [])
        await store.send(.editEnded(CanvasTestSupport.edit("second", generation: store.state.renderedRevision)))
        await settle(store)

        await store.send(.load(page: NotebookFixture.firstPage, expectedVerseCount: 3))
        await settle(store)
        #expect(store.state.loadedDrawings?.map(\.rowID) == [NotebookFixture.rowInFirst])
        #expect(store.state.loadedDrawings?.first?.lineData == Data("create-first".utf8))

        await store.send(.load(page: NotebookFixture.secondPage, expectedVerseCount: 3))
        await settle(store)
        #expect(store.state.loadedDrawings?.map(\.rowID) == [NotebookFixture.rowInSecond])
        #expect(store.state.loadedDrawings?.first?.notebook == NotebookFixture.second)
        #expect(repository.appliedPages.value == [NotebookFixture.firstPage, NotebookFixture.secondPage])
        #expect(repository.legacyCalls.value == 0)
    }

    @Test("지우기(보관)가 도는 사이 필사책을 바꿔도 보관은 지우기를 시작한 page 의 행에만 한다")
    func eraseArchivesOnlyItsNotebook() async throws {
        let repository = PageStoreRepository()
        let store = makeStore(repository, page: NotebookFixture.firstPage)
        await compose(store, NotebookFixture.firstPage)

        // 절 1(활성 행이 있는 절)을 지운다 — 보관이 붙잡힌 채 돈다.
        repository.holdNextArchive()
        await store.send(.eraseRequested(at: CGPoint(x: 10, y: 15)))
        #expect(store.state.eraseAlert != nil)
        await store.send(.eraseAlert(.presented(.confirm(verse: 1))))
        #expect(store.state.eraseTask?.page == NotebookFixture.firstPage)
        try await eventually { repository.isHoldingArchive }

        // 보관 중에 필사책을 바꾼다 — 지우기 작업은 접고, 보관은 A 의 행에서 끝난다.
        await store.send(.load(page: NotebookFixture.secondPage, expectedVerseCount: 3))
        #expect(store.state.eraseTask == nil)
        repository.releaseArchive()
        await settle(store)

        #expect(repository.archivedPages.value == [NotebookFixture.firstPage])
        #expect(store.state.page == NotebookFixture.secondPage)
        #expect(store.state.eraseTask == nil)
        #expect(repository.legacyCalls.value == 0)
    }

    @Test("설정에서 다른 필사책의 같은 장에 넣은 필기는 열린 page 에 반영하지 않는다 — 같은 page 면 저장소를 다시 읽어 본다")
    func localImportIntoOtherNotebookIsIgnored() async {
        let repository = PageStoreRepository()
        let store = makeStore(repository, page: NotebookFixture.firstPage)
        await compose(store, NotebookFixture.firstPage)
        let loads = repository.loadedPages.value.count

        await store.send(.localDrawingChanged(LocalDrawingChange(page: NotebookFixture.secondPage, date: Date(timeIntervalSince1970: 2_000))))
        await settle(store)
        #expect(store.state.arrival.phase == .idle)
        #expect(!store.state.arrival.localImport)
        #expect(repository.loadedPages.value.count == loads)

        await store.send(.localDrawingChanged(LocalDrawingChange(page: NotebookFixture.firstPage, date: Date(timeIntervalSince1970: 2_000))))
        await settle(store)
        #expect(repository.loadedPages.value.count == loads + 1)
        #expect(repository.loadedPages.value.last == NotebookFixture.firstPage)
    }
}

// MARK: - 초안 · 상태 — page 로 가른다

@Suite("필사책 바꾸기 — 초안 키 · 보이는 초안은 page 로 가른다")
@MainActor
struct NotebookSwitchDraftTesting {
    @Test("이 page 에 보이는 초안은 page 가 같은 것뿐이다 — 같은 장의 다른 번역본 · 다른 필사책 초안은 섞이지 않는다")
    func displayedDraftKeysStayInPage() {
        let kjvPage = NotebookFixture.psalmKJV.inDefaultNotebook
        var state = ChapterCanvasFeature.State(page: NotebookFixture.firstPage)
        let scope = AccountScope(key: "acct-a")
        let own = VerseDraftKey(sessionID: "now", page: NotebookFixture.firstPage, verse: 1)
        let kjv = VerseDraftKey(sessionID: "now", page: kjvPage, verse: 1)
        let second = VerseDraftKey(sessionID: "now", page: NotebookFixture.secondPage, verse: 1)
        state.drafts.records = [
            BibleDrawingRowID(raw: "own"): DraftRecord(key: own, scope: scope, revision: 1),
            BibleDrawingRowID(raw: "kjv"): DraftRecord(key: kjv, scope: scope, revision: 1),
            BibleDrawingRowID(raw: "second"): DraftRecord(key: second, scope: scope, revision: 1)
        ]
        let adoptedHere = VerseDraftKey(sessionID: "earlier", page: NotebookFixture.firstPage, verse: 2)
        let adoptedInSecond = VerseDraftKey(sessionID: "earlier", page: NotebookFixture.secondPage, verse: 2)
        state.drafts.adopted = [
            DraftVerse(page: NotebookFixture.firstPage, verse: 2): VerseDraftRef(key: adoptedHere, revision: 1),
            DraftVerse(page: NotebookFixture.secondPage, verse: 2): VerseDraftRef(key: adoptedInSecond, revision: 1)
        ]

        #expect(state.displayedDraftKeys == [own, adoptedHere])
        state.page = kjvPage
        #expect(state.displayedDraftKeys == [kjv])
        state.page = NotebookFixture.secondPage
        #expect(state.displayedDraftKeys == [second, adoptedInSecond])
    }

    @Test("다른 필사책의 같은 장에 남은 미저장분은 이 page 를 「편집한 장」 으로 만들지 않는다")
    func pendingOfOtherNotebookDoesNotMarkPageEdited() {
        var state = ChapterCanvasFeature.State(page: NotebookFixture.secondPage)
        state.pendingMutations = [NotebookFixture.rowInFirst: PendingDrawingMutation(
            revision: 1, page: NotebookFixture.firstPage, mutation: .clear(verse: 1, rowID: NotebookFixture.rowInFirst)
        )]

        #expect(state.showsOnlyStore)
        state.page = NotebookFixture.firstPage
        #expect(!state.showsOnlyStore)
    }

    @Test("초안 키는 편집의 page 를 그대로 든다 — 다른 필사책의 같은 장 초안은 그 필사책의 키다")
    func draftKeyCarriesNotebook() {
        let entry = PendingDrawingMutation(
            revision: 3, page: NotebookFixture.secondPage,
            mutation: .create(verse: 2, rowID: NotebookFixture.rowInSecond, data: Data("ink".utf8), metadata: CanvasTestSupport.metadata())
        )
        let draft = ChapterCanvasFeature.makeDraft(
            entry, sessionID: "now", base: .empty,
            provenance: VerseDraftProvenance(account: .unverified(hint: nil), knownEpochs: [], storeOwnership: nil),
            eraseGeneration: 0, now: NotebookFixture.now
        )

        #expect(draft.key == VerseDraftKey(sessionID: "now", page: NotebookFixture.secondPage, verse: 2))
        #expect(draft.key.notebook == NotebookFixture.second)
        #expect(draft.key.page == NotebookFixture.secondPage)
    }

    @Test("캔버스는 초안을 page 로 읽는다 — 다른 필사책도 옛 장 요구로 읽지 않는다")
    func draftsAreReadByPage() async throws {
        let environment = DrawingEditEnvironment.ownedForTesting
        let drafts = PageDraftStore(generation: environment.eraseGeneration)

        _ = try await ChapterCanvasFeature.loadDrafts(from: drafts, environment: environment, page: NotebookFixture.secondPage)

        #expect(!drafts.requested.value.isEmpty)
        #expect(drafts.requested.value.allSatisfy { $0 == NotebookFixture.secondPage })
        #expect(drafts.legacyCalls.value == 0)
    }

    @Test("절 행 · 이전 필사 시트의 ID 는 필사책마다 다르다 — 기본 필사책은 필사 행과 같은 권 키 그대로다")
    func identitiesIncludeNotebook() {
        let verse = BibleVerse(title: NotebookFixture.psalm, verse: 1, sentence: "여호와는 나의 목자시니")
        let firstRow = SentencesWithDrawingFeature.State(sentence: verse, notebook: .default)
        let secondRow = SentencesWithDrawingFeature.State(sentence: verse, notebook: NotebookFixture.second)
        #expect(firstRow.id == "1-19Psalms.txt/23/1")
        #expect(secondRow.id == "nb_\(NotebookFixture.second.rawValue)~1-19Psalms.txt/23/1")
        // 같은 본문이라도 다른 행이다 — 필사책만 바꿔도 행을 새로 만들어 다시 잰다.
        #expect(firstRow != secondRow)

        let firstHistory = VerseDrawingHistoryFeature.State(page: NotebookFixture.firstPage, verse: 1)
        let secondHistory = VerseDrawingHistoryFeature.State(page: NotebookFixture.secondPage, verse: 1)
        #expect(firstHistory.id == "DrewHistory.1-19Psalms.txt.23.1")
        #expect(secondHistory.id == "DrewHistory.nb_\(NotebookFixture.second.rawValue)~1-19Psalms.txt.23.1")
    }
}

// MARK: - 이전 필사 — 필사책 안에서만

@Suite("필사책 바꾸기 — 이전 필사는 필사책마다 따로다")
@MainActor
struct NotebookVerseHistoryTesting {
    /// 그 page · 절에서 `isPresent` 인 행의 키.
    private static func presentKeys(_ storeActor: SwiftDatabaseActor, page: NotebookChapter) async throws -> [String] {
        try await storeActor.verseDrawingSnapshots(page: page, verse: 1).filter(\.isPresent).map(\.rowID.raw)
    }

    @Test("이전 필사는 그 필사책의 행만 보이고, 회차를 고르면 그 필사책의 대표만 바꾼다 — 같은 절의 기본 필사책 대표는 그대로다")
    func verseHistoryIsPerNotebook() async throws {
        let (container, storeActor) = try NotebookFixture.makeDatabase([
            .init(page: NotebookFixture.firstPage, key: "first-current", seed: 1, updatedAt: 400),
            .init(page: NotebookFixture.firstPage, key: "first-older", seed: 2, isPresent: false, updatedAt: 300),
            .init(page: NotebookFixture.secondPage, key: "second-current", seed: 3, updatedAt: 200),
            .init(page: NotebookFixture.secondPage, key: "second-older", seed: 4, isPresent: false, updatedAt: 100)
        ])
        let database = withDependencies { $0.createSwiftDataActor = storeActor } operation: { DrawingDatabase() }
        let store = Store(initialState: VerseDrawingHistoryFeature.State(page: NotebookFixture.secondPage, verse: 1)) {
            VerseDrawingHistoryFeature()
        } withDependencies: {
            $0.drawingData = database
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(.ownedForTesting)
        }

        store.send(.view(.fetchDrawings))
        try await eventually { store.hasLoaded }
        #expect(store.drawings.map(\.rowID.raw) == ["second-current", "second-older"])
        #expect(store.drawings.allSatisfy { $0.notebook == NotebookFixture.second })

        let older = try #require(store.drawings.first { $0.rowID.raw == "second-older" })
        store.send(.view(.selectDrawing(older)))
        try await eventually { try await Self.presentKeys(storeActor, page: NotebookFixture.secondPage) == ["second-older"] }
        #expect(try await Self.presentKeys(storeActor, page: NotebookFixture.firstPage) == ["first-current"])
        withExtendedLifetime(container) {}
    }
}

// MARK: - 컬럼 호스트 — page 가 바뀌면 이전 컬럼을 놓는다 (R26)

@Suite("필사책 바꾸기 — 캔버스 컨트롤러의 컬럼 호스트")
@MainActor
struct NotebookColumnHostingTesting {
    /// 메모리 해제 자체는 단위 시험으로 볼 수 없다 — 놓기로 한 **결정**을 고정한다(`ChapterCanvasControllerTesting` 의 R26 시험과 같은 관용구).
    @Test("필사책만 바뀐 같은 장도 이전 컬럼을 놓는다 — 절 행이 필사책마다 새로 만들어진다 (R26)")
    func notebookChangeReleasesPreviousColumn() {
        let controller = ChapterCanvasController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
        controller.loadViewIfNeeded()

        controller.setColumn(AnyView(Color.clear), page: NotebookFixture.firstPage)
        #expect(controller.columnReleaseCount == 0)   // 첫 page 에는 놓을 것이 없다

        // 같은 장 · 다른 필사책 — 다른 page 다.
        controller.setColumn(AnyView(Color.clear), page: NotebookFixture.secondPage)
        #expect(controller.columnReleaseCount == 1)
        // 같은 page 로 다시 넣으면 놓지 않는다(SwiftUI 갱신마다 불린다). 레이아웃 전(nil)에는 판정하지 않는다.
        controller.setColumn(AnyView(Color.clear), page: NotebookFixture.secondPage)
        controller.setColumn(AnyView(Color.clear), page: nil)
        #expect(controller.columnReleaseCount == 1)

        controller.setColumn(AnyView(Color.clear), page: NotebookFixture.firstPage)
        #expect(controller.columnReleaseCount == 2)
    }
}
