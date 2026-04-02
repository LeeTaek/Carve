//
//  HeaderFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 4/2/26.
//

@testable import CarveFeature
import Testing

struct HeaderFeatureTesting {
    @Test("헤더 토글로 숨길 때 높이만큼 올리고 추적 상태를 초기화한다")
    func toggleVisibilityHidesHeaderAndResetsTracking() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.headerOffset = -18
        state.lastHeaderOffset = -18
        state.direction = .up
        state.shiftOffset = -24

        _ = HeaderFeature().reduce(into: &state, action: .toggleVisibility)

        #expect(state.isHidden)
        #expect(state.headerOffset == -72)
        #expect(state.direction == .none)
        #expect(state.shiftOffset == 0)
        #expect(state.lastHeaderOffset == -72)
    }

    @Test("위로 스크롤을 계속하면 헤더 오프셋이 높이를 넘지 않게 고정된다")
    func headerAnimationClampsOffsetWhileScrollingUp() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.direction = .up
        state.shiftOffset = -12

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-12, -120))

        #expect(state.headerOffset == -72)
    }

    @Test("탭으로 숨긴 뒤 아래로 스크롤하면 숨김 상태를 해제하고 아래 방향으로 전환한다")
    func headerAnimationClearsHiddenStateOnScrollDown() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.headerOffset = -72
        state.isHidden = true

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-10, 20))

        #expect(!state.isHidden)
        #expect(state.direction == .down)
        #expect(state.shiftOffset == 20)
        #expect(state.lastHeaderOffset == -72)
    }
}
