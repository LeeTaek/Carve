//
//  CarveNavigationFeature.swift
//  CarveFeature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Resources
import SwiftUI
import SwiftData

import ComposableArchitecture

/// Carve 전체 네비게이션 관리 Reducer
/// 성경 (제목/장) 선ㄴ택, Splitview, 상세화면 전환 담당
@Reducer
public struct CarveNavigationFeature {
    public init() { }
    @ObservableState
    public struct State {
        /// SplitView column
        public var columnVisibility: NavigationSplitViewVisibility
        /// 현재 선택된 성경 content화면 상태
        public var carveDetailState: CarveDetailFeature.State
        /// 사이드바에서 선택된 성경(List Selection과 바인딩)
        public var selectedTitle: BibleTitle?
        /// 중간 컬럼에서 선택된 장 번호(List Selection과 바인딩)
        public var selectedChapter: Int?
        /// content 화면에 띄우는 네비게이션 상태
        @Presents var detailNavigation: DetailDestination.State?
        /// 앱 전역에 공유하는 현재 성경 title
        @Shared(.appStorage("title")) public var currentTitle: TitleVO = .initialState
        
        public static let initialState = State(
            columnVisibility: .detailOnly,
            carveDetailState: .initialState
        )
    }
    public enum Action: ViewAction, CarveToolkit.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            /// 설정 화면으로 이동
            case moveToSetting
            /// NavigationSplitView를 닫고 DetailOnly로 변경
            case closeNavigationBar
            /// detail Content 안에서 네비게이션 래핑
            case detailNavigation(PresentationAction<DetailDestination.Action>)
            /// DrawingHistoryChart로 이동
            case navigationToDrewLog
        }
    }

    @CasePathable
    public enum ScopeAction {
        case carveDetailAction(CarveDetailFeature.Action)
    }
    
    /// 상세 화면에서의 Navigation Destination
    @Reducer
    public enum DetailDestination {
        /// 문장 폰트 등 설정 화면 시트
        case sentenceSettings(SentenceSettingsFeature)
        /// DrawingHistoryChart로 이동
        case drewLog(DrewLogFeature)
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.selectedTitle) { _, newValue in
                Reduce { state, _ in
                    guard let title = newValue else { return .none }
                    if state.currentTitle.title != title {
                        state.selectedChapter = nil
                    }
                    state.$currentTitle.withLock { $0.title = title }
                    return .none
                }
            }
            .onChange(of: \.selectedChapter) { _, newValue in
                Reduce { state, _ in
                    guard let selectedChapter = newValue else { return .none }
                    state.$currentTitle.withLock { $0.chapter = selectedChapter }
                    state.columnVisibility = .detailOnly
                    return .none
                }
            }
        
        Scope(state: \.carveDetailState,
              action: \.scope.carveDetailAction) {
            CarveDetailFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.titleDidTapped))))):
                return handleTitleDidTapped(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToNext))))):
                return handleMoveToNext(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToBefore))))):
                return handleMoveToBefore(state: &state)
                
            case .view(.moveToSetting):
                Log.debug("move To settings")
                return .none
                
            case .view(.closeNavigationBar):
                state.columnVisibility = .detailOnly
                return .none
                
            case .view(.navigationToDrewLog):
                state.columnVisibility = .detailOnly
                state.detailNavigation = .drewLog(.initialState)
                return .none
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.sentenceSettingsDidTapped))))):
                state.detailNavigation = .sentenceSettings(.initialState)
                return .none
                
            default: return .none
            }
        }
        .ifLet(\.$detailNavigation, action: \.view.detailNavigation)
    }
}


extension CarveNavigationFeature {
    /// 제목(타이틀)을 탭했을 때 사이드바/장 선택 상태를 동기화하고 SplitView를 모두 표시.
    private func handleTitleDidTapped(state: inout State) -> Effect<Action> {
        state.selectedTitle = state.currentTitle.title
        state.selectedChapter = state.currentTitle.chapter
        state.carveDetailState.sentenceWithDrawingState.removeAll()
        state.columnVisibility = .all
        return .none
    }
    
    /// 다음 장으로 이동하고, 이동 후 선택된 본문을 다시 로드.
    private func handleMoveToNext(state: inout State) -> Effect<Action> {
        if state.currentTitle.chapter == state.currentTitle.title.lastChapter {
            state.$currentTitle.withLock { $0.title = state.currentTitle.title.next() }
            state.$currentTitle.withLock { $0.chapter = 1 }
        } else {
            state.$currentTitle.withLock { $0.chapter += 1 }
        }
        return .run { send in
            await send(.scope(.carveDetailAction(.view(.fetchSentence))))
        }
    }
    
    /// 이전 장으로 이동하고, 이동 후 선택된 본문을 다시 로드.
    private func handleMoveToBefore(state: inout State) -> Effect<Action> {
        if state.currentTitle.chapter == 1 {
            state.$currentTitle.withLock { $0.title = state.currentTitle.title.before() }
            state.$currentTitle.withLock { $0.chapter = state.currentTitle.title.lastChapter }
        } else {
            state.$currentTitle.withLock { $0.chapter -= 1 }
        }
        return .run { send in
            await send(.scope(.carveDetailAction(.view(.fetchSentence))))
        }
    }
}
