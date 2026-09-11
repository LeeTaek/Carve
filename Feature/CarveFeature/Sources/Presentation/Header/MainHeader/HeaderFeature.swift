//
//  HeaderReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI

import ComposableArchitecture

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

    @ObservableState
    public struct State {
        @Shared(.appStorage("title")) public var currentTitle: BibleChapter = .initialState
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
        /// 필기 열을 왼쪽에 둘지. 본문 설정 버튼과 팝오버의 위치를 정한다.
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        /// 탭으로 전환한 축소 헤더 상태. 광고 영역이 생겨도 헤더는 항상 남는다.
        public var isManuallyCollapsed: Bool = false
        /// NavigationSplitView가 열려 있는지 헤더의 탐색 버튼에 전달한다.
        public var isNavigationPresented: Bool = false
        
        public enum SwipeDirection {
            case up
            case down
            case none
        }
        public static let initialState = Self(
            headerHeight: 0,
            headerOffset: 0,
            lastHeaderOffset: 0,
            shiftOffset: 0,
            isPaletteExpanded: false,
            showOnlyTitle: false
        )
    }
    public enum Action: ViewAction {
        case headerAnimation(CGFloat, CGFloat)
        case palatteAction(PencilPalatteFeature.Action)
        case sentenceSettings(PresentationAction<SentenceSettingsFeature.Action>)
        case toggleCompact
        case view(View)
        
        public enum View {
            /// 서재 아이콘을 탭해 탐색 열림 상태를 전환한다.
            case libraryDidTapped
            case titleDidTapped
            case setHeaderHeight(CGFloat)
            /// 하단 접힘 팔레트를 탭해 도구 목록을 펼친다.
            case expandPalette
            case sentenceSettingsDidTapped
            case moveToNext
            case moveToBefore

        }
    }
    
    public var body: some Reducer<State, Action> {
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

                // 본문을 읽어 내려갈 때는 도구를 접고, 되돌릴 때는 다시 펼친다.
                // 맨 위를 넘어 당긴 튕김(값이 양수)은 방향 전환이 아니다 — N-Canvas(SwiftUI ScrollView) 경로용.
                // 단일 Canvas 경로는 컨트롤러가 양 끝 튕김을 잘라서 보고한다.
                let isOverscrolledAtTop = previous > 0 || current > 0
                if isScrollingUp, !isOverscrolledAtTop {
                    state.isPaletteExpanded = false
                } else if isScrollingDown, !isOverscrolledAtTop {
                    state.isPaletteExpanded = true
                }
                
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

            case .view(.expandPalette):
                state.isPaletteExpanded = true

            case .view(.sentenceSettingsDidTapped):
                state.sentenceSettings = .initialState
                
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
        .onChange(of: \.isLeftHanded) { _, _ in
            Reduce { state, _ in
                // 팝오버의 anchor가 필기 열 쪽으로 바뀌므로, 열린 상태에서는 닫고 새 위치에서 다시 연다.
                state.sentenceSettings = nil
                return .none
            }
        }
    }

    /// 펼친 높이에서 축소 높이까지의 스크롤 이동량을 만든다. 이 값을 넘기면 헤더는 더 위로 밀리지 않는다.
    private func collapseDistance(for state: State) -> CGFloat {
        max(0, state.headerHeight - Self.compactHeight)
    }
}
