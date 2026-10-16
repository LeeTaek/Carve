//
//  CarveNavigationFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 9/11/26.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@MainActor
struct CarveNavigationFeatureTesting {
    @Test("최초 안내는 네 항목을 순서대로 넘긴 뒤 완료한다")
    func firstRunGuideAdvancesThroughFourPages() async {
        let store = TestStore(initialState: FirstRunGuideFeature.State.initialState) {
            FirstRunGuideFeature()
        }

        await store.send(.view(.nextTapped)) {
            $0.currentPage = 1
        }
        await store.send(.view(.nextTapped)) {
            $0.currentPage = 2
        }
        await store.send(.view(.nextTapped)) {
            $0.currentPage = 3
        }
        await store.send(.view(.nextTapped))
        await store.receive(\.delegate)
    }

    @Test("서재 아이콘을 닫힌 상태에서 누르면 현재 장을 선택한 3열을 연다")
    func libraryButtonOpensAllColumns() {
        var state = CarveNavigationFeature.State.initialState

        _ = CarveNavigationFeature().reduce(
            into: &state,
            action: .scope(.carveDetailAction(.scope(.headerAction(.view(.libraryDidTapped)))))
        )

        #expect(state.columnVisibility == .all)
        #expect(state.selectedTitle == state.currentTitle.title)
        #expect(state.selectedChapter == state.currentTitle.chapter)
        #expect(state.carveDetailState.headerState.isNavigationPresented)
    }

    @Test("서재 아이콘을 열린 상태에서 누르면 모든 탐색 열을 닫는다")
    func libraryButtonClosesAllColumns() {
        var state = CarveNavigationFeature.State.initialState
        state.columnVisibility = .all

        _ = CarveNavigationFeature().reduce(
            into: &state,
            action: .scope(.carveDetailAction(.scope(.headerAction(.view(.libraryDidTapped)))))
        )

        #expect(state.columnVisibility == .detailOnly)
        #expect(!state.carveDetailState.headerState.isNavigationPresented)
    }

    @Test("설정을 열면 탐색 열을 닫고 필사 화면만 남긴다")
    func moveToSettingClosesNavigationColumns() {
        var state = CarveNavigationFeature.State.initialState
        state.columnVisibility = .all
        state.carveDetailState.headerState.isNavigationPresented = true

        _ = CarveNavigationFeature().reduce(into: &state, action: .view(.moveToSetting))

        #expect(state.columnVisibility == .detailOnly)
        #expect(!state.carveDetailState.headerState.isNavigationPresented)
    }

    @Test("최초 안내는 UserDefaults에 표시 사실을 저장하고 자동으로 다시 열지 않는다")
    func firstRunGuideIsPresentedOnlyOnce() throws {
        let suite = "CarveNavigationFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var state = CarveNavigationFeature.State.initialState
        state.$hasPresentedFirstRunGuide = Shared(
            wrappedValue: false,
            .appStorage("hasSeenFirstRunGuide", store: defaults)
        )
        let reducer = CarveNavigationFeature()

        _ = reducer.reduce(into: &state, action: .view(.presentFirstRunGuide))

        #expect(state.firstRunGuide != nil)
        #expect(state.hasPresentedFirstRunGuide)
        #expect(defaults.bool(forKey: "hasSeenFirstRunGuide"))

        state.firstRunGuide = nil
        _ = reducer.reduce(into: &state, action: .view(.presentFirstRunGuide))
        #expect(state.firstRunGuide == nil)

        // 도움말의 수동 재표시는 최초 실행 여부와 관계없이 허용한다.
        _ = reducer.reduce(into: &state, action: .view(.restartFirstRunGuide))
        #expect(state.firstRunGuide != nil)

        _ = reducer.reduce(into: &state, action: .firstRunGuide(.presented(.delegate(.finished))))
        #expect(state.firstRunGuide == nil)
    }

    @Test("성경을 고르면 현재 장은 그대로 두고, 필사 기록을 받을 때까지 장 선택을 비운다")
    func bibleTitleTappedKeepsCurrentChapter() {
        var state = CarveNavigationFeature.State.initialState
        state.selectedTitle = state.currentTitle.title
        state.selectedChapter = state.currentTitle.chapter
        let currentTitle = state.currentTitle

        _ = CarveNavigationFeature().reduce(into: &state, action: .view(.bibleTitleTapped(.songOfSongs)))

        #expect(state.selectedTitle == .songOfSongs)
        #expect(state.selectedChapter == nil)
        #expect(state.currentTitle == currentTitle)
    }

    @Test(
        "필사 기록을 받으면 가장 최근에 필사한 장의 다음 장을 고른다 — 마지막 장이면 그대로, 기록이 없으면 1장",
        arguments: zip([3, 8, nil] as [Int?], [4, 8, 1])
    )
    func drawingRecordSelectsDefaultChapter(latestChapter: Int?, expectedChapter: Int) {
        var state = CarveNavigationFeature.State.initialState
        state.selectedTitle = .songOfSongs
        let drawnChapters: Set<Int> = latestChapter.map { [1, $0] } ?? []

        _ = CarveNavigationFeature().reduce(
            into: &state,
            action: .drawingRecordLoaded(.songOfSongs, .init(drawnChapters: drawnChapters, latestChapter: latestChapter))
        )

        #expect(state.selectedChapter == expectedChapter)
        #expect(state.drawnChapters[.songOfSongs] == drawnChapters)
    }

    @Test("탐색을 열며 고른 현재 장이나 그사이 고른 다른 성경의 선택은 늦게 온 필사 기록이 바꾸지 않는다")
    func drawingRecordKeepsExistingSelection() {
        var state = CarveNavigationFeature.State.initialState
        state.selectedTitle = .psalms
        state.selectedChapter = 119
        let reducer = CarveNavigationFeature()

        _ = reducer.reduce(into: &state, action: .drawingRecordLoaded(.psalms, .init(drawnChapters: [119], latestChapter: 119)))
        #expect(state.selectedChapter == 119)
        #expect(state.drawnChapters[.psalms] == [119])

        state.selectedTitle = .isaiah
        state.selectedChapter = nil
        _ = reducer.reduce(into: &state, action: .drawingRecordLoaded(.psalms, .init(drawnChapters: [119], latestChapter: 119)))
        #expect(state.selectedChapter == nil)
    }

    // MARK: 백그라운드 배치 — iPadOS 18 은 앱 전환기 스냅샷을 compact 폭으로 찍으며 분할 화면을 접었다 편다

    @Test("백그라운드 동안 분할 화면이 바인딩으로 바꾼 열 표시는 받지 않는다 — 돌아와도 닫아 둔 장 목록 열이 열리지 않는다")
    func backgroundColumnVisibilityChangeIsRefused() {
        // Given: 탐색 열을 닫아 둔 채 홈으로 나갔다
        var state = CarveNavigationFeature.State.initialState
        let reducer = CarveNavigationFeature()
        _ = reducer.reduce(into: &state, action: .view(.sceneEnteredBackground))
        #expect(state.isInBackground)

        // When: 스냅샷 배치에서 분할 화면이 접히며 열 표시를 써 넣는다(18.6 실측 detailOnly → doubleColumn)
        _ = reducer.reduce(into: &state, action: .binding(.set(\.columnVisibility, .doubleColumn)))

        // Then: 받지 않는다 — 헤더의 탐색 버튼도, 장 선택도 그대로다
        #expect(state.columnVisibility == .detailOnly)
        #expect(!state.carveDetailState.headerState.isNavigationPresented)
        #expect(state.selectedTitle == nil)

        // When: 다시 활성이 된다
        _ = reducer.reduce(into: &state, action: .view(.sceneBecameActive))

        // Then: 닫힌 그대로다
        #expect(!state.isInBackground)
        #expect(state.columnVisibility == .detailOnly)
    }

    @Test("탐색 열을 연 채 나갔으면 백그라운드 배치가 바꾸려 해도 연 그대로 남는다")
    func backgroundKeepsOpenNavigation() {
        var state = CarveNavigationFeature.State.initialState
        state.columnVisibility = .all
        state.carveDetailState.headerState.isNavigationPresented = true
        let reducer = CarveNavigationFeature()

        _ = reducer.reduce(into: &state, action: .view(.sceneEnteredBackground))
        _ = reducer.reduce(into: &state, action: .binding(.set(\.columnVisibility, .doubleColumn)))

        #expect(state.columnVisibility == .all)
        #expect(state.carveDetailState.headerState.isNavigationPresented)
    }

    @Test("활성일 때 분할 화면이 연 열 표시는 그대로 받고 지금 장을 고른다(시스템 제스처)")
    func activeColumnVisibilityChangeIsAccepted() {
        var state = CarveNavigationFeature.State.initialState

        _ = CarveNavigationFeature().reduce(into: &state, action: .binding(.set(\.columnVisibility, .doubleColumn)))

        #expect(state.columnVisibility == .doubleColumn)
        #expect(state.carveDetailState.headerState.isNavigationPresented)
        #expect(state.selectedTitle == state.currentTitle.title)
        #expect(state.selectedChapter == state.currentTitle.chapter)
    }

    @Test("백그라운드여도 리듀서가 직접 바꾸는 열 표시는 되돌리지 않는다 — 바인딩 경로만 막는다")
    func reducerVisibilityChangeInBackgroundIsKept() {
        var state = CarveNavigationFeature.State.initialState
        state.columnVisibility = .all
        let reducer = CarveNavigationFeature()

        _ = reducer.reduce(into: &state, action: .view(.sceneEnteredBackground))
        _ = reducer.reduce(into: &state, action: .view(.closeNavigationBar))

        #expect(state.columnVisibility == .detailOnly)
        #expect(!state.carveDetailState.headerState.isNavigationPresented)
    }

    // MARK: 지금 필사책 (2.2 회차별 필사책 결정 13 · 15)

    /// 기본이 아닌 필사책 — 두 번째로 만든 필사책.
    private static let secondNotebook = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000002")!)

    /// 이 시험만의 UserDefaults 에 붙은 처음 상태로 `operation` 을 돌린다 — 지금 필사책 · 지금 장 키가 다른 시험과 섞이지 않는다.
    private func withNavigationState(_ operation: (inout CarveNavigationFeature.State, UserDefaults) throws -> Void) throws {
        let suite = "CarveNavigationFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            CarveNavigationFeature.State.initialState
        }
        try operation(&state, defaults)
    }

    @Test("처음에는 기본 필사책이고, 필사책 바꾸기는 지금 필사책 키(기기마다)에 그 ID 를 쓴다")
    func switchNotebookWritesCurrentNotebookKey() throws {
        try withNavigationState { state, defaults in
            #expect(state.currentNotebook == .default)
            let currentTitle = state.currentTitle

            _ = CarveNavigationFeature().reduce(into: &state, action: .switchNotebook(Self.secondNotebook))

            #expect(state.currentNotebook == Self.secondNotebook)
            #expect(defaults.string(forKey: "currentNotebookID") == Self.secondNotebook.rawValue)
            // 장은 그대로다 — 같은 장을 그 필사책으로 다시 연다.
            #expect(state.currentTitle == currentTitle)

            _ = CarveNavigationFeature().reduce(into: &state, action: .switchNotebook(.default))
            #expect(defaults.string(forKey: "currentNotebookID") == NotebookID.default.rawValue)
        }
    }

    @Test("저장된 지금 필사책이 필사책 ID 형식이 아니면 기본 필사책으로 읽는다")
    func corruptedCurrentNotebookReadsAsDefault() throws {
        try withNavigationState { state, _ in
            for broken in ["", "nb_default", "0F3A1C2D00004000800000000000000 2", "0F3A1C2D000040008000000000000002"] {
                state.$currentNotebookID.withLock { $0 = broken }
                #expect(state.currentNotebook == .default, "「\(broken)」")
            }
        }
    }

    @Test("필사책과 장을 함께 열면 지금 필사책을 그 필사책으로 바꾼다 — 장 · 절은 장 이동으로 이어서 연다")
    func openPageWritesNotebookBeforeMovingToChapter() throws {
        try withNavigationState { state, defaults in
            let johnKJV = BibleChapter(title: .john, chapter: 3, translation: .KJV)

            _ = CarveNavigationFeature().reduce(
                into: &state,
                action: .openPage(NotebookChapter(notebook: Self.secondNotebook, chapter: johnKJV), verse: 16)
            )

            #expect(state.currentNotebook == Self.secondNotebook)
            #expect(defaults.string(forKey: "currentNotebookID") == Self.secondNotebook.rawValue)
        }
    }

    @Test("위젯 · 필사 알림 · 즐겨찾기의 장 이동은 지금 필사책을 바꾸지 않는다(결정 15)")
    func moveToChapterKeepsCurrentNotebook() throws {
        try withNavigationState { state, _ in
            let reducer = CarveNavigationFeature()
            _ = reducer.reduce(into: &state, action: .switchNotebook(Self.secondNotebook))
            let psalms = BibleChapter(title: .psalms, chapter: 23)

            _ = reducer.reduce(into: &state, action: .moveToChapter(psalms))
            _ = reducer.reduce(into: &state, action: .moveToVerse(BibleVerse(title: psalms, verse: 1, sentence: "")))

            #expect(state.currentTitle == psalms)
            #expect(state.currentNotebook == Self.secondNotebook)
        }
    }

    @Test("책장 열기는 화면 전환을 코디네이터에 맡기고 필사 화면 상태를 바꾸지 않는다")
    func moveToNotebooksLeavesStateToCoordinator() throws {
        try withNavigationState { state, _ in
            state.columnVisibility = .all
            let currentTitle = state.currentTitle

            _ = CarveNavigationFeature().reduce(into: &state, action: .view(.moveToNotebooks))

            #expect(state.columnVisibility == .all)
            #expect(state.currentTitle == currentTitle)
            #expect(state.currentNotebook == .default)
        }
    }
}

// 책장의 화면 경계(뒤로 · 고르기 · 지우기 위임)는 책장 내용과 함께 `NotebookShelfFeatureTesting.swift` 가 본다.

/// 장 목록을 선택한 장으로 옮길 때 목록 끝을 넘지 않는다(iPadOS 27.2 가로에서 제목과 목록이 내려앉던 문제).
@MainActor
struct ChapterListScrollTesting {
    @Test("맨 위 장은 가운데로 맞추지 않고 목록 맨 위에 둔다")
    func firstRowsStayAtTop() {
        #expect(CarveNavigationView.chapterListScroll(to: 1, lastChapter: 150, viewportHeight: 600) == .top)
        #expect(CarveNavigationView.chapterListScroll(to: 10, lastChapter: 150, viewportHeight: 600) == .top)
    }

    @Test("중간 장은 가운데로 맞춘다")
    func middleChapterIsCentered() {
        #expect(CarveNavigationView.chapterListScroll(to: 60, lastChapter: 150, viewportHeight: 600) == .center(60))
    }

    @Test("마지막 화면 안의 장은 목록 맨 아래에 둔다")
    func lastRowsStickToBottom() {
        #expect(CarveNavigationView.chapterListScroll(to: 150, lastChapter: 150, viewportHeight: 600) == .bottom)
        #expect(CarveNavigationView.chapterListScroll(to: 50, lastChapter: 50, viewportHeight: 400) == .bottom)
    }

    @Test("목록이 한 화면에 들어오면 맨 위에 둔다")
    func shortListStaysAtTop() {
        #expect(CarveNavigationView.chapterListScroll(to: 50, lastChapter: 50, viewportHeight: 600) == .top)
    }
}

// MARK: - 헤더의 지금 필사책 이름 · 책장 진입 (2.2 회차별 필사책 결정 9)

/// 탐색이 보낸 화면 이동 요청을 모으는 시험용 부모 — 코디네이터처럼 `CarveNavigationFeature` 를 품는다.
@Reducer
struct NotebookEntryRecorder {
    @ObservableState
    struct State {
        var carve: CarveNavigationFeature.State
    }

    enum Action {
        case carve(CarveNavigationFeature.Action)
    }

    let moves: LockIsolated<[String]>

    var body: some ReducerOf<Self> {
        Scope(state: \.carve, action: \.carve) {
            CarveNavigationFeature()
        }
        Reduce { _, action in
            if case .carve(.view(.moveToNotebooks)) = action {
                moves.withValue { $0.append("notebooks") }
            }
            return .none
        }
    }
}

/// 본문을 읽지 못하는 스텁 — 읽은 횟수를 센다. 필사책을 바꾼 뒤 본문 읽기가 캔버스 조회로 이어지지 않게 한다.
final class NavigationUnreadableText: BibleTextClient {
    struct Unreadable: Error {}

    let fetches = LockIsolated(0)

    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        fetches.withValue { $0 += 1 }
        throw Unreadable()
    }
}

@Suite("탐색 — 헤더의 지금 필사책 이름 · 책장 진입")
@MainActor
struct CarveNavigationNotebookNameTesting {
    /// 이 시험만의 UserDefaults 로 돌린다 — 지금 필사책 · 지금 장 키(기기마다)가 다른 시험과 섞이지 않는다.
    private func withDefaults(_ operation: @MainActor (UserDefaults) async throws -> Void) async throws {
        let suite = "CarveNavigationNotebookNameTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await operation(defaults)
    }

    /// 필사책 목록 · 도착 · 본문 대역을 넣은 탐색 Store. 처음 상태는 Store 의 의존성 안에서 만든다.
    private func makeStore(
        _ repository: ShelfRepositorySpy,
        defaults: UserDefaults,
        current: NotebookID = .default,
        arrivals: any CloudImportArrivalClient = StubCloudImportArrivalClient(),
        text: NavigationUnreadableText = NavigationUnreadableText()
    ) -> StoreOf<CarveNavigationFeature> {
        defaults.set(current.rawValue, forKey: "currentNotebookID")
        return Store(initialState: CarveNavigationFeature.State.initialState) {
            CarveNavigationFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
            $0.defaultInMemoryStorage = InMemoryStorage()
            $0.notebookRepository = repository
            $0.cloudImportArrivals = arrivals
            $0.bibleTextClient = text
        }
    }

    /// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("번역본 팝오버의 「책장 열기」 는 팝오버를 닫고, 서재 열 아래 「책장」 과 같이 코디네이터에 책장 열기를 알린다")
    func headerOpenNotebooksMovesToShelf() async throws {
        try await withDefaults { defaults in
            let moves = LockIsolated<[String]>([])
            let store = Store(initialState: {
                var carve = CarveNavigationFeature.State.initialState
                carve.carveDetailState.headerState.isTranslationPickerPresented = true
                return NotebookEntryRecorder.State(carve: carve)
            }()) {
                NotebookEntryRecorder(moves: moves)
            } withDependencies: {
                $0.defaultAppStorage = defaults
            }

            store.send(.carve(.scope(.carveDetailAction(.scope(.headerAction(.view(.notebooksTapped)))))))

            await waitUntil { moves.value == ["notebooks"] }
            #expect(!store.carve.carveDetailState.headerState.isTranslationPickerPresented)
        }
    }

    @Test("시작하면 필사책 목록을 한 번 읽어 헤더 부제에 지금 필사책 이름을 채운다 — 이름을 바꾼 기본 필사책은 그 이름이다")
    func startFillsHeaderName() async throws {
        try await withDefaults { defaults in
            var renamedDefault = ShelfFixture.defaultNotebook
            renamedDefault.name = "2026 시편"
            let repository = ShelfRepositorySpy([renamedDefault, ShelfFixture.secondNotebook])
            let store = makeStore(repository, defaults: defaults)
            #expect(!store.carveDetailState.headerState.isNotebookNameLoaded)

            store.send(.scope(.carveDetailAction(.view(.appeared))))

            await waitUntil { store.carveDetailState.headerState.isNotebookNameLoaded }
            #expect(store.carveDetailState.headerState.notebookName == "2026 시편")
            #expect(store.carveDetailState.headerState.isDefaultNotebook)
            #expect(repository.reads.value == 1)
        }
    }

    @Test("지금 필사책이 목록에 없으면(다른 기기에서 지움) 기본 필사책으로 돌아가고, 같은 목록으로 기본 필사책 이름을 채운다 — 목록은 한 번만 읽는다")
    func fallbackFillsDefaultNameWithoutExtraRead() async throws {
        try await withDefaults { defaults in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.thirdNotebook])
            let store = makeStore(repository, defaults: defaults, current: ShelfFixture.second)
            #expect(store.currentNotebook == ShelfFixture.second)

            store.send(.scope(.carveDetailAction(.view(.appeared))))

            await waitUntil { store.currentNotebook == .default && store.carveDetailState.headerState.isNotebookNameLoaded }
            #expect(store.carveDetailState.headerState.notebookName.isEmpty)
            #expect(store.carveDetailState.headerState.isDefaultNotebook)
            #expect(repository.reads.value == 1)
        }
    }

    @Test("iCloud 에서 받은 것이 들어오면 목록을 다시 읽어 이름을 고친다 — 다른 기기에서 지금 필사책 이름을 바꿨을 수 있다")
    func arrivalRefreshesName() async throws {
        try await withDefaults { defaults in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            let arrivals = ShelfArrivals()
            let store = makeStore(repository, defaults: defaults, arrivals: arrivals)
            store.send(.scope(.carveDetailAction(.view(.appeared))))
            await waitUntil { store.carveDetailState.headerState.isNotebookNameLoaded }
            #expect(store.carveDetailState.headerState.notebookName.isEmpty)

            repository.listed.withValue { $0[0].name = "가족 필사" }
            arrivals.continuation.yield(Date(timeIntervalSince1970: 2_000))

            await waitUntil { store.carveDetailState.headerState.notebookName == "가족 필사" }
            #expect(repository.reads.value == 2)
            arrivals.continuation.finish()
        }
    }

    @Test("필사책을 바꾸면 목록을 읽어 그 필사책 이름을 채운다 — 차트의 최근 기록으로 필사책과 장을 함께 열어도 같다")
    func switchingNotebookReadsName() async throws {
        try await withDefaults { defaults in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook])
            let store = makeStore(repository, defaults: defaults)

            store.send(.switchNotebook(ShelfFixture.second))

            await waitUntil { store.carveDetailState.headerState.notebookName == "두 번째 필사" }
            #expect(!store.carveDetailState.headerState.isDefaultNotebook)
            #expect(store.carveDetailState.headerState.isNotebookNameLoaded)

            // 이름 없는 필사책(정보 없이 행만 있다)으로 차트의 최근 기록을 연다.
            let page = NotebookChapter(notebook: ShelfFixture.third, chapter: BibleChapter(title: .john, chapter: 3))
            store.send(.openPage(page, verse: 16))

            await waitUntil { store.currentNotebook == ShelfFixture.third && store.carveDetailState.headerState.notebookName.isEmpty }
            #expect(!store.carveDetailState.headerState.isDefaultNotebook)
            #expect(repository.reads.value == 2)
        }
    }

    @Test("지금 필사책의 이름을 바꾼 뒤 같은 필사책으로 알려 오면 장은 다시 열지 않고 이름만 다시 읽는다")
    func sameNotebookSwitchOnlyRefreshesName() async throws {
        try await withDefaults { defaults in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            let text = NavigationUnreadableText()
            let store = makeStore(repository, defaults: defaults, text: text)
            store.send(.scope(.carveDetailAction(.view(.appeared))))
            await waitUntil { store.carveDetailState.headerState.isNotebookNameLoaded && text.fetches.value == 1 }

            // 책장에서 지금 필사책(기본)의 이름을 바꿨다 — 코디네이터가 같은 필사책으로 `switchNotebook` 을 보낸다.
            repository.listed.withValue { $0[0].name = "2026 사순절" }
            store.send(.switchNotebook(.default))

            await waitUntil { store.carveDetailState.headerState.notebookName == "2026 사순절" }
            #expect(text.fetches.value == 1)
            #expect(store.carveDetailState.chapterCanvas.page.notebook == .default)
        }
    }

    @Test("전체 삭제(모든 필사 데이터 삭제) 뒤에는 헤더가 이름 없는 기본 필사책이다 — 모든 필사책 정보가 지워졌으므로 목록을 읽지 않는다")
    func eraseAllResetsHeaderName() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = CarveDetailFeature.State.initialState
            state.headerState.notebookName = "두 번째 필사"
            state.headerState.isDefaultNotebook = false
            state.headerState.isNotebookNameLoaded = true
            // 설정이 지금 필사책 키를 기본으로 돌린 뒤 세대를 올렸다(키는 처음부터 기본이다).
            state.$drawingDataRevision.withLock { $0 += 1 }

            _ = CarveDetailFeature().reduce(into: &state, action: .view(.drawingDataRevisionChanged))

            #expect(state.headerState.notebookName.isEmpty)
            #expect(state.headerState.isDefaultNotebook)
            #expect(state.headerState.isNotebookNameLoaded)
        }
    }
}
