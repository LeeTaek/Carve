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
    @ObservableState
    public struct State {
        @Shared(.appStorage("title")) public var currentTitle: BibleChapter = .initialState
        public var headerHeight: CGFloat
        public var headerOffset: CGFloat
        public var lastHeaderOffset: CGFloat
        public var direction: SwipeDirection = .none
        public var shiftOffset: CGFloat
        public var showPalatte: Bool
        public var showOnlyTitle: Bool
        public var palatteSetting: PencilPalatteFeature.State = .initialState
        /// 헤더 본문 설정 버튼에 붙는 팝오버 상태.
        @Presents public var sentenceSettings: SentenceSettingsFeature.State?
        /// 필기 열을 왼쪽에 둘지. 본문 설정 버튼과 팝오버의 위치를 정한다.
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        /// 탭으로 헤더 숨김/보임 상태
        public var isHidden: Bool = false
        
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
            showPalatte: false,
            showOnlyTitle: false
        )
    }
    public enum Action: ViewAction {
        case headerAnimation(CGFloat, CGFloat)
        case palatteAction(PencilPalatteFeature.Action)
        case sentenceSettings(PresentationAction<SentenceSettingsFeature.Action>)
        case toggleVisibility
        case view(View)
        
        public enum View {
            case titleDidTapped
            case setHeaderHeight(CGFloat)
            case pencilConfigDidTapped
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

                if isScrollingDown, state.isHidden {
                    // 스크롤로 다시 열기 시작 → 탭으로 숨긴 상태 해제
                    state.isHidden = false
                    state.direction = .down
                    state.shiftOffset = current
                    state.lastHeaderOffset = state.headerOffset
                }
                
                if isScrollingUp {
                    if state.direction != .up, current < 0 {
                        state.shiftOffset = current - state.headerOffset
                        state.direction = .up
                        state.lastHeaderOffset = state.headerHeight
                    }

                    let offset = current < 0 ? (current - state.shiftOffset) : 0
                    state.headerOffset = (-offset < state.headerHeight
                                          ? (offset < 0 ? offset : 0)
                                          : -state.headerHeight)
                } else if isScrollingDown {
                    if state.direction != .down {
                        state.shiftOffset = current
                        state.direction = .down
                        state.lastHeaderOffset = state.headerOffset
                    }

                    let offset = state.lastHeaderOffset + (current - state.shiftOffset)
                    state.headerOffset = (offset > 0 ? 0 : offset)
                }

            case .view(.pencilConfigDidTapped):
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.showPalatte.toggle()
                }

            case .view(.sentenceSettingsDidTapped):
                state.sentenceSettings = .initialState
                
            case .toggleVisibility:
                state.isHidden.toggle()
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    if state.isHidden {
                        state.headerOffset = -state.headerHeight
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
}
