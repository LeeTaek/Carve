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

    @Test("최초 안내는 UserDefaults에 표시 사실을 저장하고 자동으로 다시 열지 않는다")
    func firstRunGuideIsPresentedOnlyOnce() throws {
        let suite = "CarveNavigationFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            var state = CarveNavigationFeature.State.initialState
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
    }
}
