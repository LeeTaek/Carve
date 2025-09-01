//
//  DrawingChartPagerFeature.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI

import ComposableArchitecture

@Reducer
public struct DrawingChartPagerFeature {
    @ObservableState
    public struct State {
        var chartPageState: IdentifiedArrayOf<DrawingChartPageFeature.State> = []
        /// 현재 표시되는 페이지의 인덱스
        var index: Int = 1
        /// 차트의 현재 스크롤 상태
        var isScrolling: Bool = false
        /// 드래그 제스처(GestureState)
        var translation: CGFloat = 0
        /// 페이지 전환시의 애니메이션 효과
        var animation: Animation? = .interactiveSpring()
        /// 보여줄 차트의 날짜
        var pageDate: Date = .now

        public static var initialState = Self()
    }
    
    @Dependency(\.continuousClock) var clock
    
    public enum Action: BindableAction, ViewAction {
        case binding(BindingAction<State>)
        case view(View)
        case chartPageAction(IdentifiedActionOf<DrawingChartPageFeature>)
        /// 페이지 넘어간걸 알림
        case didMove(_ index: Int)
        case update
        
        
        public enum View {
            /// 데이터 업데이트
            case dragUpdated(traslation: CGFloat)
            case dragOnEnded(translation: CGFloat, width: CGFloat)
        }
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.translation) { _, newValue in
                Reduce { state, _ in
                    state.isScrolling = (newValue != 0)
                    return .none
                }
            }
        
        Reduce { state, action in
            switch action {
            case .view(.dragUpdated(let translation)):
                state.translation = translation
                state.animation = .interactiveSpring()
            case .view(.dragOnEnded(let translation, let width)):
                state.animation = .smooth(duration: 0.25)
                
                let offset = translation / width
                let pageCount = 3
                let newIndex = min(max(Int((CGFloat(state.index) - offset).rounded()), 0), pageCount - 1)
                
                let pages = state.chartPageState.map { $0.page }
                let data = state.chartPageState.map { $0.entries }
                
                if newIndex != state.index, canMove(page: pages[newIndex], data: data[newIndex]) {
                    state.index = newIndex
                
                    return .run { @MainActor send in
                        try await clock.sleep(for: .milliseconds(200))
                        send(.didMove(newIndex))
                    }
                } else {
                    state.animation = .interactiveSpring()
                }
                
            case .didMove(let index):
                state.pageDate = state.chartPageState[index].page.date
                state.chartPageState[1] = state.chartPageState[index]
                return .send(.update)
                                
            case .update:
                // TODO: - update 로직
                state.index = 1
                state.animation = .interactiveSpring()
                
            default: break
            }
            return .none
        }
    }
}

extension DrawingChartPagerFeature {
    private func canMove(page: ChartDataPage, data: ChartDataCollection) -> Bool {
        page.xScale.upperBound >= data.dateRange.lowerBound &&
        page.xScale.lowerBound <= data.dateRange.upperBound
    }
}
