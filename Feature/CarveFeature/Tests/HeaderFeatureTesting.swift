//
//  HeaderFeatureTesting.swift
//  FeatureCarveTest
//
//  Created by Codex on 4/2/26.
//

@testable import CarveFeature
import Domain
import Foundation
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

    @Test("팔레트는 헤더가 완전히 접히거나 펼쳐진 뒤에만 함께 전환한다")
    func headerAnimationUpdatesPaletteVisibility() async {
        var state = HeaderFeature.State.initialState
        state.headerHeight = 118
        state.isPaletteExpanded = true

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-10, -20))

        #expect(state.isPaletteExpanded)

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-20, -61))

        #expect(state.headerOffset == -40)
        #expect(!state.isPaletteExpanded)

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-61, -60))

        #expect(!state.isPaletteExpanded)

        _ = HeaderFeature().reduce(into: &state, action: .headerAnimation(-60, -20))

        #expect(state.headerOffset == 0)

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

    @Test("헤더 제목을 누르면 번역본 고르기 팝오버를 연다")
    func titleDidTappedPresentsTranslationPicker() async {
        var state = HeaderFeature.State.initialState

        _ = HeaderFeature().reduce(into: &state, action: .view(.titleDidTapped))

        #expect(state.isTranslationPickerPresented)
    }

    @Test("번역본을 고르면 헤더는 고르기 팝오버만 닫는다 — 번역본 전환은 탐색 리듀서가 한다")
    func translationSelectedClosesPickerOnly() async {
        var state = HeaderFeature.State.initialState
        state.isTranslationPickerPresented = true
        let title = state.currentTitle

        _ = HeaderFeature().reduce(into: &state, action: .view(.translationSelected(.KJV)))

        #expect(!state.isTranslationPickerPresented)
        #expect(state.currentTitle == title)
    }

    @Test("고르지 않고 바깥을 눌러 닫으면 고르기 팝오버 상태를 내린다")
    func translationPickerDismissedClosesPicker() async {
        var state = HeaderFeature.State.initialState
        state.isTranslationPickerPresented = true

        _ = HeaderFeature().reduce(into: &state, action: .view(.translationPickerDismissed))

        #expect(!state.isTranslationPickerPresented)
    }

    @Test("축소 헤더는 상태바가 높아도 44pt 버튼 줄을 담도록 늘어나고, 펼친 높이는 그대로다")
    func displayedHeightContainsControlsForTallerStatusBar() {
        // 상태바 24pt: 시안 규격 78pt 그대로.
        #expect(HeaderFeature.displayedHeight(collapseProgress: 1, safeAreaTop: 24) == 78)
        #expect(HeaderFeature.controlsTopPadding(collapseProgress: 1, safeAreaTop: 24) + 44 == 78)

        // 상태바 32pt(iPadOS 26 iPad mini): 버튼 줄 아래끝 32 + 10 + 44 = 86pt 까지 그린다.
        #expect(HeaderFeature.displayedHeight(collapseProgress: 1, safeAreaTop: 32) == 86)
        #expect(HeaderFeature.controlsTopPadding(collapseProgress: 1, safeAreaTop: 32) + 44 == 86)

        // 펼친 높이는 본문 시작점이라 상태바와 무관하게 118pt 이고, 그 안에 버튼 줄이 들어간다.
        #expect(HeaderFeature.displayedHeight(collapseProgress: 0, safeAreaTop: 32) == 118)
        #expect(HeaderFeature.controlsTopPadding(collapseProgress: 0, safeAreaTop: 32) + 44 <= 118)
    }

}

/// 헤더 부제의 지금 필사책 이름 · 번역본 팝오버 끝 「책장 열기」(2.2 회차별 필사책 결정 9).
@Suite("헤더 — 지금 필사책 이름 · 책장 열기")
@MainActor
struct HeaderNotebookTesting {
    private static let korean = Locale(identifier: "ko")
    private static let english = Locale(identifier: "en")

    @Test("처음 헤더는 필사책 이름을 아직 읽지 않았다 — 부제에 필사책 칸이 없다")
    func initialHeaderHasNoNotebookName() {
        let state = HeaderFeature.State.initialState

        #expect(!state.isNotebookNameLoaded)
        #expect(state.notebookName.isEmpty)
        #expect(HeaderView.notebookLabel(
            name: state.notebookName, isDefault: state.isDefaultNotebook, isLoaded: state.isNotebookNameLoaded, locale: Self.korean
        ) == nil)
    }

    @Test("번역본 팝오버의 「책장 열기」 는 팝오버만 닫는다 — 책장은 탐색 리듀서가 연다")
    func notebooksTappedClosesPicker() {
        var state = HeaderFeature.State.initialState
        state.isTranslationPickerPresented = true
        let title = state.currentTitle

        _ = HeaderFeature().reduce(into: &state, action: .view(.notebooksTapped))

        #expect(!state.isTranslationPickerPresented)
        #expect(state.currentTitle == title)
    }

    @Test("부제 첫 칸은 지금 필사책 이름 — 사용자가 지은 이름은 옮기지 않고, 이름이 없으면 화면 언어의 기본 표시다")
    func notebookLabelFollowsNameAndLanguage() {
        #expect(HeaderView.notebookLabel(name: "", isDefault: true, isLoaded: true, locale: Self.korean) == "첫 번째 필사")
        #expect(HeaderView.notebookLabel(name: "", isDefault: true, isLoaded: true, locale: Self.english) == "First Notebook")
        #expect(HeaderView.notebookLabel(name: "", isDefault: false, isLoaded: true, locale: Self.korean) == "이름 없는 필사책")
        #expect(HeaderView.notebookLabel(name: "", isDefault: false, isLoaded: true, locale: Self.english) == "Untitled Notebook")
        #expect(HeaderView.notebookLabel(name: "두 번째 필사", isDefault: false, isLoaded: true, locale: Self.english) == "두 번째 필사")
        #expect(HeaderView.notebookLabel(name: "두 번째 필사", isDefault: false, isLoaded: false, locale: Self.korean) == nil)
    }

    @Test("제목 VoiceOver 값은 지금 필사책 이름과 번역본 전체 이름이다 — 이름을 읽기 전에는 번역본만")
    func titleAccessibilityValueIncludesNotebook() {
        #expect(HeaderView.titleAccessibilityValue(notebookLabel: "두 번째 필사", translation: .NKRV, locale: Self.korean) == "두 번째 필사, 개역개정")
        #expect(
            HeaderView.titleAccessibilityValue(notebookLabel: "First Notebook", translation: .KJV, locale: Self.english)
                == "First Notebook, King James Version"
        )
        #expect(HeaderView.titleAccessibilityValue(notebookLabel: nil, translation: .KJV, locale: Self.english) == "King James Version")
    }
}
