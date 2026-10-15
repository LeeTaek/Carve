//
//  CarveNavigationFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 9/11/26.
//

@testable import CarveFeature
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
}

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
