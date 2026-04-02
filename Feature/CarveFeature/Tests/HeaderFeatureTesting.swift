//
//  HeaderFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 4/2/26.
//

@testable import CarveFeature
import Testing

struct HeaderFeatureTesting {
    @Test("헤더를 다시 토글해 보이면 오프셋을 0으로 되돌리고 추적 상태를 초기화한다")
    func toggleVisibilityShowsHeaderAndResetsTracking() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.headerOffset = -72
        state.lastHeaderOffset = -72
        state.direction = .down
        state.shiftOffset = 18
        state.isHidden = true

        _ = HeaderFeature().reduce(into: &state, action: .toggleVisibility)

        #expect(!state.isHidden)
        #expect(state.headerOffset == 0)
        #expect(state.direction == .none)
        #expect(state.shiftOffset == 0)
        #expect(state.lastHeaderOffset == 0)
    }

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

    @Test("아래로 스크롤하면 헤더 오프셋은 0을 넘지 않고 현재 위치를 기준으로 전환한다")
    func headerAnimationClampsOffsetAtZeroWhileScrollingDown() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.headerOffset = -24
        state.direction = .up
        state.shiftOffset = -12

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-12, 32))

        #expect(state.direction == .down)
        #expect(state.shiftOffset == 32)
        #expect(state.lastHeaderOffset == -24)
        #expect(state.headerOffset == -24)
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

    @Test("헤더 높이 설정 액션은 측정한 높이를 상태에 반영한다")
    func setHeaderHeightUpdatesState() async {
        var state = HeaderFeature.State.initialState

        _ = HeaderFeature().reduce(into: &state, action: .view(.setHeaderHeight(88)))

        #expect(state.headerHeight == 88)
    }
}
