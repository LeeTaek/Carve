//
//  CarveNavigationFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 9/11/26.
//

@testable import CarveFeature
import Testing

struct CarveNavigationFeatureTesting {
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
}
