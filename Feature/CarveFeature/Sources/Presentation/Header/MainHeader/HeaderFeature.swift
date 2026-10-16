//
//  HeaderReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

@Reducer
public struct HeaderFeature {
    /// 본문 시작 위치를 고정하는 펼친 헤더 높이(L1 · L3).
    public static let expandedHeight: CGFloat = 118
    /// 스크롤 중에도 화면 상단에 남는 축소 헤더 높이(L2 · L3).
    public static let compactHeight: CGFloat = 78
    /// 하단 펼침 팔레트가 마지막 절을 가리지 않도록 비우는 높이.
    public static let expandedPaletteBottomInset: CGFloat = 96
    /// 하단 접힘 팔레트와 도구 이름이 마지막 절을 가리지 않도록 비우는 높이.
    public static let collapsedPaletteBottomInset: CGFloat = 112
    /// 펼친 헤더에서 상태바 아래부터 버튼 줄까지의 여백.
    static let expandedControlsTopInset: CGFloat = 28
    /// 축소 헤더에서 상태바 아래부터 버튼 줄까지의 여백.
    static let compactControlsTopInset: CGFloat = 10

    /// 버튼 줄 위 여백(화면 맨 위부터). 상태바 높이에 축소 진행률(0 펼침 · 1 축소)에 따른 여백을 더한다.
    static func controlsTopPadding(collapseProgress: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        let insetRange = expandedControlsTopInset - compactControlsTopInset
        return safeAreaTop + expandedControlsTopInset - insetRange * collapseProgress
    }

    /// 화면에 그리는 헤더 높이(화면 맨 위부터).
    ///
    /// 축소 높이 78pt 는 상태바 24pt 기준(24 + 10 + 버튼 줄 44)이다. 상태바가 더 높은 기기(iPadOS 26 의 iPad mini 는 32pt)에서는
    /// 버튼 줄이 헤더 아래로 삐져나오지 않도록 그만큼 늘린다. 펼친 높이는 본문 시작점이라 바꾸지 않는다.
    static func displayedHeight(collapseProgress: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        let compact = max(compactHeight, safeAreaTop + compactControlsTopInset + CarveSize.minimumHitTarget)
        return expandedHeight - (expandedHeight - compact) * collapseProgress
    }

    @ObservableState
    public struct State {
        /// 지금 장(번역본 포함) — 탐색(`CarveNavigationFeature`)과 같은 공유 값이다. 저장값이 없으면 처음 설치 기본 장이다.
        @Shared(.codableAppStorage("title")) public var currentTitle: BibleChapter = .firstLaunch
        public var headerHeight: CGFloat
        public var headerOffset: CGFloat
        public var lastHeaderOffset: CGFloat
        public var direction: SwipeDirection = .none
        public var shiftOffset: CGFloat
        /// 하단 도구 팔레트의 펼침 상태. 접힌 상태에도 현재 도구와 실행 취소는 남는다.
        public var isPaletteExpanded: Bool
        public var showOnlyTitle: Bool
        public var palatteSetting: PencilPalatteFeature.State = .initialState
        /// 헤더 본문 설정 버튼에 붙는 팝오버 상태.
        @Presents public var sentenceSettings: SentenceSettingsFeature.State?
        /// 헤더 제목을 눌러 연 번역본 고르기 팝오버(영어 현지화 결정 19). 고르거나 바깥을 누르면 닫힌다.
        public var isTranslationPickerPresented: Bool = false
        /// 지금 필사책 이름 — 헤더 부제 첫 칸(「두 번째 필사 · 개역개정 · 구약 / 시편」, 2.2 결정 9). 사용자가 지은 이름 그대로다(옮기지 않는다).
        /// 빈 문자열은 필사책 정보에 이름이 없다는 뜻 — 뷰가 환경 locale 로 「첫 번째 필사」(기본 필사책) · 「이름 없는 필사책」(그 밖)을 보인다.
        /// 탐색(`CarveNavigationFeature`)이 시작 · 필사책 바꾸기 · iCloud 도착 때 필사책 목록을 읽어 채운다.
        public var notebookName: String = ""
        /// 지금 필사책이 기본 필사책인가 — 이름이 없을 때 어느 기본 표시를 쓸지 고른다.
        public var isDefaultNotebook: Bool = true
        /// 지금 필사책 이름을 한 번이라도 읽었는가. 읽기 전(시작 직후)에는 부제에 필사책 칸을 두지 않는다 — 다른 이름이 잠깐 보이지 않게.
        public var isNotebookNameLoaded: Bool = false
        /// 필기 열을 왼쪽에 둘지. 헤더 버튼 위치는 바꾸지 않는다 — 서재 쪽에 버튼이 늘면 헤더 광고 자리가 사라진다.
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        /// 탭으로 전환한 축소 헤더 상태. 광고 영역이 생겨도 헤더는 항상 남는다.
        public var isManuallyCollapsed: Bool = false
        /// NavigationSplitView가 열려 있는지 헤더의 탐색 버튼에 전달한다.
        public var isNavigationPresented: Bool = false
        /// 헤더 줄 네이티브 광고(시안 K2). 필사하는 동안 계속 보이는 자리라 만료되면 바로 새로 받는다.
        public var adSlot: SponsorAdSlotFeature.State = .init(placement: .headerStrip, refreshesOnExpiry: true)
        
        public enum SwipeDirection {
            case up
            case down
            case none
        }
        /// 팔레트 상태(`PKInkingTool.InkType`)를 담아 Sendable 이 아니므로 저장 프로퍼티 대신 계산 프로퍼티다.
        public static var initialState: Self {
            Self(
                headerHeight: 0,
                headerOffset: 0,
                lastHeaderOffset: 0,
                shiftOffset: 0,
                isPaletteExpanded: false,
                showOnlyTitle: false
            )
        }
    }
    public enum Action: ViewAction {
        case headerAnimation(CGFloat, CGFloat)
        case palatteAction(PencilPalatteFeature.Action)
        case sentenceSettings(PresentationAction<SentenceSettingsFeature.Action>)
        case toggleCompact
        case adSlot(SponsorAdSlotFeature.Action)
        case view(View)

        public enum View {
            /// 헤더가 화면에 나타남 — 헤더 줄 광고를 받는다.
            case onAppear
            /// 서재 아이콘을 탭해 탐색 열림 상태를 전환한다.
            case libraryDidTapped
            /// 헤더 제목을 탭해 번역본 고르기 팝오버를 연다(영어 현지화 결정 19).
            case titleDidTapped
            /// 번역본 고르기 팝오버가 고르지 않고 닫힘 — 바깥을 누르는 등.
            case translationPickerDismissed
            /// 번역본 고르기에서 번역본을 고름 — 탐색 리듀서가 같은 권 · 장 · 지금 보던 절로 바꾼다(영어 현지화 결정 9 · 19)
            case translationSelected(Translation)
            /// 번역본 고르기 팝오버 끝의 「책장 열기」 — 팝오버를 닫고, 탐색 리듀서가 책장을 연다(2.2 결정 9)
            case notebooksTapped
            case setHeaderHeight(CGFloat)
            /// 하단 접힘 팔레트를 탭해 도구 목록을 펼친다.
            case expandPalette
            case sentenceSettingsDidTapped
            case moveToNext
            case moveToBefore

        }
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.adSlot, action: \.adSlot) {
            SponsorAdSlotFeature()
        }

        Scope(state: \.palatteSetting, action: \.palatteAction) {
            PencilPalatteFeature()
        }
        .ifLet(\.$sentenceSettings, action: \.sentenceSettings) {
            SentenceSettingsFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.setHeaderHeight(let height)):
                state.headerHeight = height
            case .headerAnimation(let previous, let current):
                let isScrollingDown = current > previous
                let isScrollingUp   = current < previous
                let collapseDistance = collapseDistance(for: state)

                if isScrollingDown, state.isManuallyCollapsed {
                    // 탭으로 축소한 헤더는 아래로 스크롤하면 다시 펼친다.
                    state.isManuallyCollapsed = false
                    state.direction = .down
                    state.shiftOffset = current
                    state.headerOffset = -collapseDistance
                    state.lastHeaderOffset = -collapseDistance
                }

                let isOverscrolledAtTop = previous > 0 || current > 0

                if isScrollingUp {
                    if state.direction != .up, current < 0 {
                        state.shiftOffset = current - state.headerOffset
                        state.direction = .up
                        state.lastHeaderOffset = collapseDistance
                    }

                    let offset = current < 0 ? (current - state.shiftOffset) : 0
                    state.headerOffset = (-offset < collapseDistance
                                          ? (offset < 0 ? offset : 0)
                                          : -collapseDistance)
                } else if isScrollingDown {
                    if state.direction != .down {
                        state.shiftOffset = current
                        state.direction = .down
                        state.lastHeaderOffset = state.headerOffset
                    }

                    let offset = state.lastHeaderOffset + (current - state.shiftOffset)
                    state.headerOffset = (offset > 0 ? 0 : offset)
                }

                // 미세한 방향 전환에는 반응하지 않고, 헤더가 끝까지 접히거나 펼쳐졌을 때 팔레트도 함께 전환한다.
                if isScrollingUp, !isOverscrolledAtTop, state.headerOffset <= -collapseDistance {
                    state.isPaletteExpanded = false
                } else if isScrollingDown, !isOverscrolledAtTop, state.headerOffset >= 0 {
                    state.isPaletteExpanded = true
                }

            case .view(.onAppear):
                return .send(.adSlot(.startLoad))

            case .view(.expandPalette):
                state.isPaletteExpanded = true

            case .view(.sentenceSettingsDidTapped):
                state.sentenceSettings = .initialState

            case .view(.titleDidTapped):
                state.isTranslationPickerPresented = true

            case .view(.translationPickerDismissed):
                state.isTranslationPickerPresented = false

            case .view(.translationSelected):
                // 번역본 전환은 탐색 리듀서가 한다(`CarveNavigationFeature.switchTranslation`). 헤더는 고르기 팝오버만 닫는다.
                state.isTranslationPickerPresented = false

            case .view(.notebooksTapped):
                // 책장 열기는 탐색 리듀서가 코디네이터에 알린다(`CarveNavigationFeature` → `.view(.moveToNotebooks)`). 헤더는 팝오버만 닫는다.
                state.isTranslationPickerPresented = false

            case .toggleCompact:
                state.isManuallyCollapsed.toggle()
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    if state.isManuallyCollapsed {
                        state.headerOffset = -collapseDistance(for: state)
                    } else {
                        state.headerOffset = 0
                    }
                }
                
                state.direction = .none
                state.shiftOffset = 0
                state.lastHeaderOffset = state.headerOffset

            default: break
            }
            return .none
        }
    }

    /// 펼친 높이에서 축소 높이까지의 스크롤 이동량을 만든다. 이 값을 넘기면 헤더는 더 위로 밀리지 않는다.
    private func collapseDistance(for state: State) -> CGFloat {
        max(0, state.headerHeight - Self.compactHeight)
    }
}
