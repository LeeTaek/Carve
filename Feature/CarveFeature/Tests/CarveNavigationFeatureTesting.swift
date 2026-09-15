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
}
