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
        @Shared(.appStorage("title")) public var currentTitle: BibleChapter = .initialState
        /// 최초 필사 안내 팝업 상태
        @Presents public var firstRunGuide: FirstRunGuideFeature.State?
        /// 최초 필사 안내를 한 번이라도 표시했는지 저장한다.
        ///
        /// `@Shared(.appStorage(...))`는 UserDefaults에 연결되므로 앱을 다시 실행해도 값이 유지된다.
        /// 키 이름은 이전 구현과의 호환성을 위해 유지한다.
        @Shared(.appStorage("hasSeenFirstRunGuide")) public var hasPresentedFirstRunGuide = false
        
        public static var initialState: Self {
            State(
                columnVisibility: .detailOnly,
                carveDetailState: .initialState
            )
        }
    }
    public enum Action: ViewAction, CarveToolkit.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case firstRunGuide(PresentationAction<FirstRunGuideFeature.Action>)
        case moveToChapter(BibleChapter)
        case moveToVerse(BibleVerse)
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            /// 설정 화면으로 이동
            case moveToSetting
            /// 차트 화면으로 이동
            case moveToChart
            /// NavigationSplitView를 닫고 DetailOnly로 변경
            case closeNavigationBar
            /// detail Content 안에서 네비게이션 래핑
            case detailNavigation(PresentationAction<DetailDestination.Action>)
            /// DrawingHistoryChart로 이동
            case navigationToDrewLog
            /// 최초 필사 안내를 표시
            case presentFirstRunGuide
            /// 설정의 도움말에서 최초 필사 안내를 다시 표시
            case restartFirstRunGuide
            /// 앱이 비활성화되기 전 단일 Canvas의 미저장분을 저장
            case appWillResignActive
            /// 장 선택 버튼에서 도메인 장 이동을 요청
            case chapterTapped(BibleChapter)
        }
    }

    @CasePathable
    public enum ScopeAction {
        case carveDetailAction(CarveDetailFeature.Action)
    }
    
    /// 상세 화면에서의 Navigation Destination
    @Reducer
    public enum DetailDestination {
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
                    syncHeaderNavigationState(state: &state)
                    // 바인딩으로 장을 선택한 경로도 본문을 새로 읽는다.
                    return .send(.scope(.carveDetailAction(.view(.fetchSentence))))
                }
            }
            .onChange(of: \.columnVisibility) { _, _ in
                Reduce { state, _ in
                    syncHeaderNavigationState(state: &state)
                    return .none
                }
            }
        
        Scope(state: \.carveDetailState,
              action: \.scope.carveDetailAction) {
            CarveDetailFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .moveToChapter(let chapter):
                state.selectedTitle = chapter.title
                state.selectedChapter = chapter.chapter
                state.$currentTitle.withLock { $0 = chapter }
                state.columnVisibility = .detailOnly
                syncHeaderNavigationState(state: &state)
                return .run { send in
                    await send(.scope(.carveDetailAction(.view(.fetchSentence))))
                }
                
            case .moveToVerse(let verse):
                state.selectedTitle = verse.title.title
                state.selectedChapter = verse.title.chapter
                state.$currentTitle.withLock { $0 = verse.title }
                state.columnVisibility = .detailOnly
                syncHeaderNavigationState(state: &state)
                return .merge(
                    .send(.scope(.carveDetailAction(.setScrollTarget(verse)))),
                    .run { send in
                        await send(.scope(.carveDetailAction(.view(.fetchSentence))))
                    }
                )
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.titleDidTapped))))):
                return handleTitleDidTapped(state: &state)

            case .scope(.carveDetailAction(.scope(.headerAction(.view(.libraryDidTapped))))):
                return toggleNavigation(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToNext))))):
                return handleMoveToNext(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToBefore))))):
                return handleMoveToBefore(state: &state)
                
            case .view(.moveToSetting):
                Log.debug("move To settings")
                return .none
                
            case .view(.moveToChart):
                Log.debug("move To chart")
                return .none
                
            case .view(.closeNavigationBar):
                state.columnVisibility = .detailOnly
                syncHeaderNavigationState(state: &state)
                return .none

            case .view(.navigationToDrewLog):
                state.columnVisibility = .detailOnly
                syncHeaderNavigationState(state: &state)
                state.detailNavigation = .drewLog(.initialState)
                return .none

            case .view(.presentFirstRunGuide):
                guard !state.hasPresentedFirstRunGuide, state.firstRunGuide == nil else { return .none }
                state.$hasPresentedFirstRunGuide.withLock { $0 = true }
                state.firstRunGuide = .initialState
                return .none

            case .view(.restartFirstRunGuide):
                guard state.firstRunGuide == nil else { return .none }
                state.firstRunGuide = .initialState
                return .none

            case .firstRunGuide(.presented(.delegate(.finished))):
                state.firstRunGuide = nil
                return .none

            case .view(.appWillResignActive):
                return .send(.scope(.carveDetailAction(.view(.appWillResignActive))))

            case .view(.chapterTapped(let chapter)):
                return .send(.moveToChapter(chapter))

            default: return .none
            }
        }
        .ifLet(\.$detailNavigation, action: \.view.detailNavigation)
        .ifLet(\.$firstRunGuide, action: \.firstRunGuide) {
            FirstRunGuideFeature()
        }
    }
}


extension CarveNavigationFeature {
    /// 제목(타이틀)을 탭했을 때 사이드바/장 선택 상태를 동기화하고 SplitView를 모두 표시.
    private func handleTitleDidTapped(state: inout State) -> Effect<Action> {
        state.selectedTitle = state.currentTitle.title
        state.selectedChapter = state.currentTitle.chapter
        state.columnVisibility = .all
        syncHeaderNavigationState(state: &state)
        return .none
    }

    /// 서재 아이콘으로 탐색을 열고 닫는다. 현재가 detailOnly이면 3열을, 일부라도 열려 있으면 detailOnly를 선택한다.
    private func toggleNavigation(state: inout State) -> Effect<Action> {
        if state.columnVisibility == .detailOnly {
            state.selectedTitle = state.currentTitle.title
            state.selectedChapter = state.currentTitle.chapter
            state.columnVisibility = .all
        } else {
            state.columnVisibility = .detailOnly
        }
        syncHeaderNavigationState(state: &state)
        return .none
    }

    /// SplitView의 실제 표시 상태를 상세 헤더의 탐색 버튼과 동기화한다.
    private func syncHeaderNavigationState(state: inout State) {
        state.carveDetailState.headerState.isNavigationPresented = state.columnVisibility != .detailOnly
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
