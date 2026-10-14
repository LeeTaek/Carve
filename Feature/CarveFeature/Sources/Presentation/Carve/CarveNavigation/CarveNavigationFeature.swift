//
//  CarveNavigationFeature.swift
//  CarveFeature
//
//  Created by 이택성 on 1/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Domain
import Resources
import SwiftUI

import ComposableArchitecture
import UIComponents

/// Carve 전체 네비게이션 관리 Reducer
/// 성경 (제목/장) 선ㄴ택, Splitview, 상세화면 전환 담당
@Reducer
public struct CarveNavigationFeature: Sendable {
    public init() { }
    @ObservableState
    public struct State {
        /// SplitView column
        public var columnVisibility: NavigationSplitViewVisibility
        /// 현재 선택된 성경 content화면 상태
        public var carveDetailState: CarveDetailFeature.State
        /// 성경 열에서 고른 성경. 장 목록은 이 성경의 장을 보여주며, 장을 고르기 전에는 `currentTitle` 을 바꾸지 않는다.
        public var selectedTitle: BibleTitle?
        /// 장 목록에서 강조할 장 번호. 성경을 고른 뒤 필사 기록을 받기 전까지는 nil 이다.
        public var selectedChapter: Int?
        /// 성경별로 필사 기록이 있는 장(지금 번역본). 탐색을 열거나 성경을 고를 때마다 새로 읽고, 번역본을 바꾸면 비운다.
        public var drawnChapters: [BibleTitle: Set<Int>] = [:]
        /// content 화면에 띄우는 네비게이션 상태
        @Presents var detailNavigation: DetailDestination.State?
        /// 앱 전역에 공유하는 현재 장(번역본 포함). 지금 번역본은 이 장의 `translation` 이다(결정 13).
        /// 저장값이 없으면(처음 설치) 기기 언어로 정한 장이다(`BibleChapter.firstLaunch`).
        @Shared(.codableAppStorage("title")) public var currentTitle: BibleChapter = .firstLaunch
        /// 최초 필사 안내 팝업 상태
        @Presents public var firstRunGuide: FirstRunGuideFeature.State?
        /// 최초 필사 안내를 한 번이라도 표시했는지 저장한다.
        ///
        /// `@Shared(.appStorage(...))`는 UserDefaults에 연결되므로 앱을 다시 실행해도 값이 유지된다.
        /// 키 이름은 이전 구현과의 호환성을 위해 유지한다.
        @Shared(.appStorage("hasSeenFirstRunGuide")) public var hasPresentedFirstRunGuide = false
        /// 탐색 사이드바 하단 네이티브 광고(시안 K3). 사이드바를 열 때 받고, 만료되면 비웠다가 다음에 열 때 받는다.
        public var sidebarAdSlot: SponsorAdSlotFeature.State = .init(placement: .sidebarCard)

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
        /// 장 목록에 쓸 성경 한 권의 필사 기록을 받음
        case drawingRecordLoaded(BibleTitle, BibleTitleDrawingRecord)
        /// 다른 화면(즐겨찾기 목록)에서 즐겨찾기가 바뀌었다 — 필사 화면의 별 표시를 다시 읽는다
        case refreshFavorites
        /// 탐색 열을 모두 열고 지금 장을 고른 목록으로 시작한다 — 실행 인자 `-UITestRoute navigation` 이 쓴다(서재 버튼은 열고 닫기를 바꾼다)
        case openNavigation
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            /// 설정 화면으로 이동
            case moveToSetting
            /// 차트 화면으로 이동
            case moveToChart
            /// 즐겨찾기 목록으로 이동 — 화면 전환은 `AppCoordinatorFeature` 가 한다
            case moveToFavorites
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
            /// 성경 열에서 성경을 선택
            case bibleTitleTapped(BibleTitle)
            /// 장 선택 버튼에서 도메인 장 이동을 요청
            case chapterTapped(BibleChapter)
            /// 사이드바가 화면에 나타남 — 하단 광고가 없거나 만료됐으면 받는다
            case sidebarAppeared
        }
    }

    @CasePathable
    public enum ScopeAction {
        case carveDetailAction(CarveDetailFeature.Action)
        case sidebarAdSlotAction(SponsorAdSlotFeature.Action)
    }
    
    /// 상세 화면에서의 Navigation Destination
    @Reducer
    public enum DetailDestination {
        /// DrawingHistoryChart로 이동
        case drewLog(DrewLogFeature)
    }
    
    @Dependency(\.drawingData) var drawingContext

    /// 비동기 작업 취소용 ID.
    enum CancelID: Hashable {
        /// 장 목록에 칠할 필사 기록 조회. 번역본을 바꾸면 이전 번역본의 늦은 결과를 버린다.
        case drawingRecord
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.columnVisibility) { oldValue, newValue in
                Reduce { state, _ in
                    syncHeaderNavigationState(state: &state)
                    // 시스템 제스처로 탐색을 연 경우에도 현재 장을 선택한 목록으로 시작한다.
                    guard oldValue == .detailOnly, newValue != .detailOnly else { return .none }
                    return selectCurrentChapter(state: &state)
                }
            }
        
        Scope(state: \.carveDetailState,
              action: \.scope.carveDetailAction) {
            CarveDetailFeature()
        }

        Scope(state: \.sidebarAdSlot,
              action: \.scope.sidebarAdSlotAction) {
            SponsorAdSlotFeature()
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
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(let translation)))))):
                // 헤더 제목 메뉴에서 고른 번역본(결정 19) — 같은 권 · 장 · 지금 보던 절로 바꾼다(결정 9).
                return switchTranslation(state: &state, to: translation)

            case .openNavigation:
                return openNavigation(state: &state)

            case .scope(.carveDetailAction(.scope(.headerAction(.view(.libraryDidTapped))))):
                return toggleNavigation(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToNext))))):
                return handleMoveToNext(state: &state)
                
            case .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToBefore))))):
                return handleMoveToBefore(state: &state)
                
            case .view(.moveToSetting):
                Log.debug("move To settings")
                // 설정은 필사 화면 위 오버레이로 뜬다. 탐색 열이 뒤에 열린 채 남지 않도록 detail만 남긴다.
                state.columnVisibility = .detailOnly
                syncHeaderNavigationState(state: &state)
                return .none
                
            case .view(.moveToChart):
                Log.debug("move To chart")
                return .none

            case .view(.moveToFavorites):
                Log.debug("move To favorites")
                return .none

            case .refreshFavorites:
                return .send(.scope(.carveDetailAction(.reloadFavorites)))
                
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

            case .view(.bibleTitleTapped(let title)):
                guard state.selectedTitle != title else { return .none }
                state.selectedTitle = title
                // 필사 기록을 받으면 기본 장을 고른다. 장을 고르기 전까지 현재 장(currentTitle)과 헤더는 그대로 둔다.
                state.selectedChapter = nil
                return loadDrawingRecord(of: title, translation: state.currentTitle.translation)

            case .drawingRecordLoaded(let title, let record):
                state.drawnChapters[title] = record.drawnChapters
                // 성경을 고르고 기록을 기다리는 중일 때만 기본 장을 고른다.
                // 탐색을 열며 선택한 현재 장이나, 그사이 고른 다른 성경의 선택은 건드리지 않는다.
                guard state.selectedTitle == title, state.selectedChapter == nil else { return .none }
                state.selectedChapter = Self.defaultChapter(of: title, latestDrawnChapter: record.latestChapter)
                return .none

            case .view(.sidebarAppeared):
                return .send(.scope(.sidebarAdSlotAction(.startLoad)))

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
    /// 탐색 열을 모두 연다 — 사이드바 · 장 선택 상태를 지금 장에 맞추고 SplitView 를 모두 표시한다.
    /// 헤더 제목은 번역본 메뉴라(결정 19) 실행 인자 경로(`openNavigation`)만 이 함수를 부른다.
    private func openNavigation(state: inout State) -> Effect<Action> {
        let effect = selectCurrentChapter(state: &state)
        state.columnVisibility = .all
        syncHeaderNavigationState(state: &state)
        return effect
    }

    /// 서재 아이콘으로 탐색을 열고 닫는다. 현재가 detailOnly이면 3열을, 일부라도 열려 있으면 detailOnly를 선택한다.
    private func toggleNavigation(state: inout State) -> Effect<Action> {
        var effect: Effect<Action> = .none
        if state.columnVisibility == .detailOnly {
            effect = selectCurrentChapter(state: &state)
            state.columnVisibility = .all
        } else {
            state.columnVisibility = .detailOnly
        }
        syncHeaderNavigationState(state: &state)
        return effect
    }

    /// 탐색을 열 때 현재 장을 선택한 목록으로 시작하고, 현재 성경의 필사 기록을 읽는다.
    private func selectCurrentChapter(state: inout State) -> Effect<Action> {
        state.selectedTitle = state.currentTitle.title
        state.selectedChapter = state.currentTitle.chapter
        return loadDrawingRecord(of: state.currentTitle.title, translation: state.currentTitle.translation)
    }

    /// 장 목록에 칠할 필사 기록을 읽는다. 읽지 못하면 기록이 없는 성경처럼 다룬다.
    /// - Parameters:
    ///   - title: 기록을 읽을 성경.
    ///   - translation: 지금 번역본 — 필사 기록은 번역본마다 따로다.
    /// - Returns: 조회 효과. 번역본을 바꾸면(`switchTranslation`) 취소돼 늦은 결과가 새 번역본의 목록을 칠하지 않는다.
    private func loadDrawingRecord(of title: BibleTitle, translation: Translation) -> Effect<Action> {
        .run { send in
            do {
                let record = try await drawingContext.fetchDrawingRecord(title: title, translation: translation)
                await send(.drawingRecordLoaded(title, record))
            } catch {
                Log.error("fetch drawing record error", error)
                await send(.drawingRecordLoaded(title, BibleTitleDrawingRecord()))
            }
        }
        .cancellable(id: CancelID.drawingRecord)
    }

    /// 번역본을 바꾼다(결정 9) — 지금 장의 `translation` 만 바꾸고 같은 권 · 장 · 지금 보던 절로 간다.
    ///
    /// 장 이동(`moveToChapter`)과 같은 경로다 — 탐색을 닫고 본문을 다시 읽으면(`fetchSentence`) 단일 Canvas 가 이전 번역본 장의
    /// 미저장분을 그 장으로 저장(flush)하고 새 번역본 장을 읽는다. 보던 절이 새 번역본에 없으면 바로 앞 절로 스크롤한다(`CarveDetailFeature.scrollToTop`).
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - translation: 고른 번역본. 지금 번역본이면 아무것도 하지 않는다.
    /// - Returns: 이전 번역본의 필사 기록 조회 취소와 본문 다시 읽기.
    private func switchTranslation(state: inout State, to translation: Translation) -> Effect<Action> {
        guard translation != state.currentTitle.translation else { return .none }
        var chapter = state.currentTitle
        chapter.translation = translation
        // 장이 바뀌기 전에 읽는다 — 보던 장의 레이아웃 · 스크롤 위치로 정한다.
        let viewingVerse = state.carveDetailState.viewingVerse
        state.carveDetailState.scrollTargetVerse = viewingVerse
        // 보던 절은 보이는 맨 위 절이므로 맨 위에 다시 둔다 — 아래쪽에 두면 바꿀 때마다 앞 절로 밀린다(2.1.0 출시 시험 EN-M1).
        state.carveDetailState.scrollTargetAnchor = .top
        // 장 목록의 필사 기록은 번역본마다 따로다. 이전 번역본의 기록을 지우고, 탐색을 다시 열 때 새 번역본으로 읽는다.
        state.drawnChapters = [:]
        state.selectedTitle = chapter.title
        state.selectedChapter = chapter.chapter
        state.$currentTitle.withLock { $0 = chapter }
        state.columnVisibility = .detailOnly
        syncHeaderNavigationState(state: &state)
        return .merge(
            .cancel(id: CancelID.drawingRecord),
            .run { send in
                await send(.scope(.carveDetailAction(.view(.fetchSentence))))
            }
        )
    }

    /// 성경을 골랐을 때 먼저 선택할 장. 가장 최근에 필사한 장의 다음 장이고, 그 장이 마지막 장이면 마지막 장, 기록이 없으면 1장이다.
    static func defaultChapter(of title: BibleTitle, latestDrawnChapter: Int?) -> Int {
        guard let latestDrawnChapter else { return 1 }
        return min(latestDrawnChapter + 1, title.lastChapter)
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
