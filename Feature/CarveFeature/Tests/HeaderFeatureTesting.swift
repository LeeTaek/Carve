//
//  HeaderFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 4/2/26.
//

@testable import CarveFeature
import Testing

struct HeaderFeatureTesting {
    @Test("축소 헤더를 다시 토글하면 펼치고 추적 상태를 초기화한다")
    func toggleCompactExpandsHeaderAndResetsTracking() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.headerOffset = -40
        state.lastHeaderOffset = -40
        state.direction = .down
        state.shiftOffset = 18
        state.isManuallyCollapsed = true

        _ = HeaderFeature().reduce(into: &state, action: .toggleCompact)

        #expect(!state.isManuallyCollapsed)
        #expect(state.headerOffset == 0)
        #expect(state.direction == .none)
        #expect(state.shiftOffset == 0)
        #expect(state.lastHeaderOffset == 0)
    }

    @Test("헤더 토글은 화면에서 없애지 않고 축소 상태로 만들며 추적 상태를 초기화한다")
    func toggleCompactCollapsesHeaderAndResetsTracking() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.headerOffset = -18
        state.lastHeaderOffset = -18
        state.direction = .up
        state.shiftOffset = -24

        _ = HeaderFeature().reduce(into: &state, action: .toggleCompact)

        #expect(state.isManuallyCollapsed)
        #expect(state.headerOffset == -40)
        #expect(state.direction == .none)
        #expect(state.shiftOffset == 0)
        #expect(state.lastHeaderOffset == -40)
    }

    @Test("위로 스크롤을 계속하면 헤더 오프셋이 높이를 넘지 않게 고정된다")
    func headerAnimationClampsOffsetWhileScrollingUp() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.direction = .up
        state.shiftOffset = -12

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-12, -120))

        #expect(state.headerOffset == -40)
    }

    @Test("아래로 스크롤하면 헤더 오프셋은 0을 넘지 않고 현재 위치를 기준으로 전환한다")
    func headerAnimationClampsOffsetAtZeroWhileScrollingDown() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.headerOffset = -24
        state.direction = .up
        state.shiftOffset = -12

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-12, 32))

        #expect(state.direction == .down)
        #expect(state.shiftOffset == 32)
        #expect(state.lastHeaderOffset == -24)
        #expect(state.headerOffset == -24)
    }

    @Test("탭으로 축소한 뒤 아래로 스크롤하면 펼침 상태로 전환한다")
    func headerAnimationClearsManualCollapseOnScrollDown() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.headerOffset = -40
        state.isManuallyCollapsed = true

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-10, 20))

        #expect(!state.isManuallyCollapsed)
        #expect(state.direction == .down)
        #expect(state.shiftOffset == 20)
        #expect(state.lastHeaderOffset == -40)
    }

    @Test("본문을 읽어 내려가면 팔레트를 접고 되돌리면 다시 펼친다")
    func headerAnimationUpdatesPaletteVisibility() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.isPaletteExpanded = true

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-10, -20))

        #expect(!state.isPaletteExpanded)

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-20, -10))

        #expect(state.isPaletteExpanded)
    }

    @Test("헤더 높이를 전달받으면 상태에 그대로 반영한다")
    func setHeaderHeightStoresMeasuredHeight() async {
        var state = HeaderFeature.State.initialState

        _ = HeaderFeature().reduce(into: &state, action: .view(.setHeaderHeight(88)))

        #expect(state.headerHeight == 88)
        #expect(state.headerOffset == 0)
    }

    @Test("접힌 하단 팔레트 탭은 팔레트만 펼치고 헤더 상태는 바꾸지 않는다")
    func expandPaletteDoesNotChangeHeaderLayout() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 72
        state.headerOffset = -24

        _ = HeaderFeature().reduce(into: &state, action: .view(.expandPalette))

        #expect(state.isPaletteExpanded)
        #expect(state.headerHeight == 72)
        #expect(state.headerOffset == -24)
    }

    @Test("본문 설정 버튼은 헤더에 붙는 설정 팝오버 상태를 연다")
    func sentenceSettingsDidTappedPresentsSettings() async {
        var state = HeaderFeature.State.initialState

        _ = HeaderFeature().reduce(into: &state, action: .view(.sentenceSettingsDidTapped))

        #expect(state.sentenceSettings != nil)
    }

}
