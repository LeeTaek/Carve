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
        /// 성경별로 필사 기록이 있는 장(지금 필사책 · 번역본). 탐색을 열거나 성경을 고를 때마다 새로 읽고, 번역본 · 필사책을 바꾸면 비운다.
        public var drawnChapters: [BibleTitle: Set<Int>] = [:]
        /// content 화면에 띄우는 네비게이션 상태
        @Presents var detailNavigation: DetailDestination.State?
        /// 앱 전역에 공유하는 현재 장(번역본 포함). 지금 번역본은 이 장의 `translation` 이다(결정 13).
        /// 저장값이 없으면(처음 설치) 기기 언어로 정한 장이다(`BibleChapter.firstLaunch`).
        @Shared(.codableAppStorage("title")) public var currentTitle: BibleChapter = .firstLaunch
        /// 지금 필사책의 `NotebookID.rawValue`(기기마다, 2.2 결정 13). 읽을 때는 `currentNotebook` 을 쓴다 — 깨진 값은 기본 필사책으로 읽는다.
        @Shared(.currentNotebookID) public var currentNotebookID: String
        /// 최초 필사 안내 팝업 상태
        @Presents public var firstRunGuide: FirstRunGuideFeature.State?
        /// 최초 필사 안내를 한 번이라도 표시했는지 저장한다.
        ///
        /// `@Shared(.appStorage(...))`는 UserDefaults에 연결되므로 앱을 다시 실행해도 값이 유지된다.
        /// 키 이름은 이전 구현과의 호환성을 위해 유지한다.
        @Shared(.appStorage("hasSeenFirstRunGuide")) public var hasPresentedFirstRunGuide = false
        /// 탐색 사이드바 하단 네이티브 광고(시안 K3). 사이드바를 열 때 받고, 만료되면 비웠다가 다음에 열 때 받는다.
        public var sidebarAdSlot: SponsorAdSlotFeature.State = .init(placement: .sidebarCard)
        /// 앱이 백그라운드에 들어가 아직 다시 활성이 되지 않았다. 그동안 분할 화면이 바인딩으로 바꾸는 열 표시는 받지 않는다.
        var isInBackground = false
        /// 지금 필사책이 필사책 목록에 있는지 보는 일(시작 때 한 번 · iCloud 도착마다)을 걸었다 — 필사 화면이 처음 나타날 때 한 번만 건다.
        var isWatchingNotebookList = false

        public static var initialState: Self {
            State(
                columnVisibility: .detailOnly,
                carveDetailState: .initialState
            )
        }

        /// 지금 필사책. 저장값이 필사책 ID 형식이 아니면(깨진 값) 기본 필사책이다.
        public var currentNotebook: NotebookID {
            NotebookID(rawValue: currentNotebookID) ?? .default
        }
    }
    public enum Action: ViewAction, CarveToolkit.ScopeAction, BindableAction {
        case binding(BindingAction<State>)
        case firstRunGuide(PresentationAction<FirstRunGuideFeature.Action>)
        case moveToChapter(BibleChapter)
        case moveToVerse(BibleVerse)
        /// 지금 필사책을 바꾸고 지금 장을 그 필사책으로 다시 연다 — 책장에서 필사책을 고르거나, 책장에 머문 채 지금 필사책이 바뀌면 코디네이터가 보낸다.
        case switchNotebook(NotebookID)
        /// 필사책과 장을 함께 연다 — 차트의 최근 장 · 절을 고르면 코디네이터가 보낸다. `verse` 가 있으면 그 절로 간다.
        case openPage(NotebookChapter, verse: Int?)
        /// 지금 필사책이 필사책 목록에 있는지 다시 본다 — iCloud 에서 받은 것이 저장소에 들어왔다(다른 기기에서 지웠을 수 있다).
        case checkCurrentNotebook
        /// 지금 필사책이 목록에 있는지 본 결과. 앞 값은 볼 때의 지금 필사책이다 — 그사이 필사책이 바뀌었으면 결과를 버린다.
        case currentNotebookChecked(NotebookID, isListed: Bool)
        /// 필사책 목록을 읽었다(시작 · iCloud 도착 · 필사책 바꾸기) — 헤더 부제에 지금 필사책 이름을 채운다(2.2 결정 9).
        case notebookListRead([NotebookSnapshot])
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
            /// 책장(필사책 고르기 · 관리)으로 이동 — 화면 전환은 `AppCoordinatorFeature` 가 한다
            case moveToNotebooks
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
            /// 앱이 백그라운드로 들어갔다 — 다시 활성이 될 때까지 시스템 배치가 바꾸는 열 표시 · 필사 컬럼 실측을 받지 않는다
            case sceneEnteredBackground
            /// 앱이 다시 활성이 됐다
            case sceneBecameActive
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
    @Dependency(\.notebookRepository) var notebookRepository
    @Dependency(\.cloudImportArrivals) var cloudImportArrivals

    /// 비동기 작업 취소용 ID.
    enum CancelID: Hashable {
        /// 장 목록에 칠할 필사 기록 조회. 번역본 · 필사책을 바꾸면 이전 번역본 · 필사책의 늦은 결과를 버린다.
        case drawingRecord
        /// 필사책 목록 조회 — 지금 필사책이 목록에 있는지 보기와 헤더 이름 읽기. 새로 읽으면 앞 조회를 버린다(마지막 목록이 이긴다).
        case notebookCheck
        /// iCloud 도착 구독 — 도착마다 지금 필사책을 다시 본다.
        case notebookArrivals
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.columnVisibility) { oldValue, newValue in
                Reduce { state, _ in
                    // iPadOS 18 은 백그라운드에서 앱 전환기 스냅샷을 compact 폭으로 찍는다. 그때 분할 화면이 접히며 열 표시를
                    // `detailOnly` → `doubleColumn` 으로 써 넣어, 돌아오면 닫아 둔 장 목록 열이 열려 있었다(2026-10-15 18.6).
                    // 사용자가 연 것이 아니므로 되돌린다. 리듀서가 직접 바꾼 값(장 이동 등)은 이 바인딩 경로를 지나지 않는다.
                    if state.isInBackground {
                        state.columnVisibility = oldValue
                        return .none
                    }
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
                
            case .switchNotebook(let notebook):
                // 책장에서 고름 · 만듦 · 지금 필사책을 지워 기본으로 · 지금 필사책의 이름을 바꿈 — 헤더 이름은 늘 다시 읽는다.
                // 같은 필사책이면 장은 다시 열지 않는다(`switchNotebook(state:to:)`).
                return .merge(switchNotebook(state: &state, to: notebook), readNotebookList())

            case let .openPage(page, verse):
                // 필사책을 먼저 바꾸고, 장 · 절은 위젯 · 즐겨찾기와 같은 장 이동(`moveToChapter` · `moveToVerse`)으로 연다 — 본문을 다시 읽을 때
                // (`setSentence`) 새 필사책의 page 가 열리고, 앞 page 의 미저장분은 앞 page 로 저장된다. 장 이동이 탐색을 닫으므로 칠한 장은
                // 비우기만 한다 — 다시 열 때 새 필사책으로 읽는다. 필사책이 바뀌면 헤더 이름을 다시 읽는다.
                var notebookChange: Effect<Action> = .none
                if Self.changesNotebook(state, to: page.notebook) {
                    state.drawnChapters = [:]
                    notebookChange = .merge(.cancel(id: CancelID.drawingRecord), readNotebookList())
                }
                state.$currentNotebookID.withLock { $0 = page.notebook.rawValue }
                guard let verse else { return .merge(notebookChange, .send(.moveToChapter(page.chapter))) }
                return .merge(notebookChange, .send(.moveToVerse(BibleVerse(title: page.chapter, verse: verse, sentence: ""))))

            case .scope(.carveDetailAction(.view(.appeared))):
                // 시작 — 지금 필사책이 목록에 있는지 보고(다른 기기에서 지웠으면 기본 필사책으로), iCloud 도착마다 다시 본다(결정 13).
                // 같은 목록으로 헤더 부제의 지금 필사책 이름을 채운다(2.2 결정 9).
                // 필사 화면은 사이드바를 닫을 때마다 다시 나타나므로 한 번만 건다. 필사 화면 자신의 본문 읽기는 `CarveDetailFeature` 가 한다.
                guard !state.isWatchingNotebookList else { return .none }
                state.isWatchingNotebookList = true
                return .merge(checkCurrentNotebook(state: state), observeNotebookArrivals())

            case .checkCurrentNotebook:
                return checkCurrentNotebook(state: state)

            case let .currentNotebookChecked(checked, isListed):
                // 본 사이 필사책이 바뀌었으면(책장에서 고름 · 새로 만듦) 그 결과는 지금 필사책의 것이 아니다.
                guard !isListed, checked == state.currentNotebook else { return .none }
                Log.info("지금 필사책이 필사책 목록에 없다(다른 기기에서 지웠을 수 있다) — 기본 필사책으로 돌아간다")
                // 헤더 이름은 같은 조회가 뒤이어 보내는 목록(`notebookListRead`)으로 채운다 — 목록을 다시 읽지 않는다.
                return switchNotebook(state: &state, to: .default)

            case .notebookListRead(let notebooks):
                fillHeaderNotebookName(state: &state, from: notebooks)
                return .none

            case .scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(let translation)))))):
                // 헤더 제목 메뉴에서 고른 번역본(결정 19) — 같은 권 · 장 · 지금 보던 절로 바꾼다(결정 9).
                return switchTranslation(state: &state, to: translation)

            case .scope(.carveDetailAction(.scope(.headerAction(.view(.notebooksTapped))))):
                // 번역본 팝오버 끝의 「책장 열기」(2.2 결정 9) — 서재 열 아래 「책장」 과 같이 코디네이터가 책장을 쌓는다. 헤더는 팝오버를 이미 닫았다.
                return .send(.view(.moveToNotebooks))

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

            case .view(.moveToNotebooks):
                Log.debug("move To notebooks")
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

            case .view(.sceneEnteredBackground):
                state.isInBackground = true
                return .send(.scope(.carveDetailAction(.view(.sceneEnteredBackground))))

            case .view(.sceneBecameActive):
                state.isInBackground = false
                return .send(.scope(.carveDetailAction(.view(.sceneBecameActive))))

            case .view(.chapterTapped(let chapter)):
                return .send(.moveToChapter(chapter))

            case .view(.bibleTitleTapped(let title)):
                guard state.selectedTitle != title else { return .none }
                state.selectedTitle = title
                // 필사 기록을 받으면 기본 장을 고른다. 장을 고르기 전까지 현재 장(currentTitle)과 헤더는 그대로 둔다.
                state.selectedChapter = nil
                return loadDrawingRecord(of: title, translation: state.currentTitle.translation, notebook: state.currentNotebook)

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
        return loadDrawingRecord(of: state.currentTitle.title, translation: state.currentTitle.translation, notebook: state.currentNotebook)
    }

    /// 장 목록에 칠할 필사 기록을 읽는다. 읽지 못하면 기록이 없는 성경처럼 다룬다.
    /// - Parameters:
    ///   - title: 기록을 읽을 성경.
    ///   - translation: 지금 번역본 — 필사 기록은 번역본마다 따로다.
    ///   - notebook: 지금 필사책 — 필사 기록은 필사책마다 따로다. 기본값이 없다(필사책 결정 12).
    /// - Returns: 조회 효과. 번역본 · 필사책을 바꾸면(`switchTranslation` · `switchNotebook`) 취소돼 늦은 결과가 새 목록을 칠하지 않는다.
    private func loadDrawingRecord(of title: BibleTitle, translation: Translation, notebook: NotebookID) -> Effect<Action> {
        .run { send in
            do {
                let record = try await drawingContext.fetchDrawingRecord(notebook: notebook, title: title, translation: translation)
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
    /// 필사책은 그대로다(필사책 결정 8) — 같은 필사책의 그 번역본 page 를 연다. 그 번역본에 쓴 적이 없으면 빈 종이다.
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

    // MARK: - 지금 필사책 (2.2 「회차별 필사책」 결정 13 · 설계 §6-8)

    /// 지금 필사책을 바꾼다 — 키를 쓰고, 열린 장을 그 필사책으로 다시 연다. **장 바꾸기와 같은 흐름**이다.
    ///
    /// 키를 **먼저** 쓰고 본문을 다시 읽는다(`fetchSentence` → `setSentence` 가 그 키로 page 를 지어 캔버스 `load(page:)`). 캔버스는 page 전환을
    /// 장 전환과 똑같이 다룬다 — 앞 필사책의 대기 명령 · 지우기 작업은 앞 page 를 들고 있어 앞 필사책으로 저장되고, 새 page 를 읽는다.
    /// 보던 절은 지킨다(번역본 바꾸기와 같이 보이는 맨 위 절을 맨 위에). 탐색 열은 그대로 두고, 칠한 장은 새 필사책으로 다시 칠한다.
    ///
    /// - 캔버스가 이미 그 필사책을 열고 있으면 다시 읽지 않는다 — 같은 page 를 다시 읽으면 행 ID 가 같아 레이아웃을 다시 재지 않는다.
    ///   책장은 만들기 · 지우기에서 키를 먼저 쓰고 알리므로, 다시 읽을지는 키가 아니라 캔버스가 연 page 로 정한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - notebook: 새 지금 필사책.
    /// - Returns: 칠한 장 다시 읽기와 본문 다시 읽기. 이미 그 필사책이면 없음. 부작용: 지금 필사책 키(UserDefaults)를 쓴다.
    private func switchNotebook(state: inout State, to notebook: NotebookID) -> Effect<Action> {
        let changes = Self.changesNotebook(state, to: notebook)
        let isShowing = state.carveDetailState.chapterCanvas.page.notebook == notebook
        state.$currentNotebookID.withLock { $0 = notebook.rawValue }
        guard changes else { return .none }
        // 칠한 장은 필사책마다 따로다 — 앞 필사책으로 칠한 장을 지운다.
        state.drawnChapters = [:]
        var follow: [Effect<Action>] = []
        if !isShowing {
            // 장이 바뀌기 전에 읽는다 — 보던 장의 레이아웃 · 스크롤 위치로 정한다(`switchTranslation` 과 같다).
            let viewingVerse = state.carveDetailState.viewingVerse
            state.carveDetailState.scrollTargetVerse = viewingVerse
            state.carveDetailState.scrollTargetAnchor = .top
            follow.append(.run { send in
                await send(.scope(.carveDetailAction(.view(.fetchSentence))))
            })
        }
        // 탐색이 열려 있으면 고른 성경을 새 필사책으로 다시 칠한다. 닫혀 있으면 다시 열 때 읽는다(`selectCurrentChapter`).
        if state.columnVisibility != .detailOnly, let title = state.selectedTitle {
            follow.append(loadDrawingRecord(of: title, translation: state.currentTitle.translation, notebook: notebook))
        }
        // 앞 필사책의 기록 조회를 먼저 버린 뒤 새로 읽는다 — 같은 취소 ID 라 순서가 바뀌면 새 조회까지 버린다.
        return .concatenate(.cancel(id: CancelID.drawingRecord), .merge(follow))
    }

    /// 지금 필사책이 그 필사책으로 바뀌는가 — 키 또는 캔버스가 연 page 의 필사책이 다르면 바뀐다.
    ///
    /// 키만 보지 않는다 — 책장은 만들기 · 지우기에서 키를 먼저 쓰고 알리므로 그때 키는 이미 새 필사책이고, 화면(캔버스 · 칠한 장)은 아직 앞 필사책이다.
    static func changesNotebook(_ state: State, to notebook: NotebookID) -> Bool {
        notebook != state.currentNotebook || notebook != state.carveDetailState.chapterCanvas.page.notebook
    }

    /// 지금 필사책이 필사책 목록에 있는지 본다 — 다른 기기에서 지웠으면 목록에 없다(결정 13). 결과는 `currentNotebookChecked` 로 온다.
    /// 같은 목록으로 헤더 부제의 지금 필사책 이름도 채운다(`notebookListRead`, 2.2 결정 9) — 이름을 위해 목록을 따로 읽지 않는다.
    /// - Returns: 목록 조회 한 번. 기본 필사책은 늘 목록에 있어 이름만 채운다. 읽지 못하면 아무것도 하지 않는다 — 목록을 모르고 기본으로 돌리지 않는다.
    private func checkCurrentNotebook(state: State) -> Effect<Action> {
        let checked = state.currentNotebook
        return .run { [notebookRepository] send in
            do {
                let notebooks = try await notebookRepository.notebooks()
                if !checked.isDefault {
                    await send(.currentNotebookChecked(checked, isListed: notebooks.contains { $0.id == checked }))
                }
                // 위에서 기본 필사책으로 돌아갔으면 기본 필사책의 이름이 채워진다 — 같은 목록에 늘 있다.
                await send(.notebookListRead(notebooks))
            } catch {
                Log.error("필사책 목록을 읽지 못했다 — 지금 필사책 · 헤더 이름을 그대로 둔다", error)
            }
        }
        .cancellable(id: CancelID.notebookCheck, cancelInFlight: true)
    }

    /// 필사책 목록을 읽어 헤더 부제의 지금 필사책 이름을 채운다(`notebookListRead`) — 필사책을 바꿨거나 지금 필사책의 이름을 바꿨을 때.
    /// 지금 필사책이 목록에 있는지는 여기서 보지 않는다 — 방금 고른 필사책이고, 다른 기기에서 지운 것은 시작 · iCloud 도착 확인이 잡는다.
    /// - Returns: 목록 조회 한 번(`notebookCheck` 와 같은 취소 ID — 마지막 목록이 이긴다). 읽지 못하면 이름을 그대로 둔다.
    private func readNotebookList() -> Effect<Action> {
        .run { [notebookRepository] send in
            do {
                await send(.notebookListRead(try await notebookRepository.notebooks()))
            } catch {
                Log.error("필사책 목록을 읽지 못했다 — 헤더의 필사책 이름을 그대로 둔다", error)
            }
        }
        .cancellable(id: CancelID.notebookCheck, cancelInFlight: true)
    }

    /// 헤더 부제의 지금 필사책 이름을 읽은 목록으로 채운다(2.2 결정 9). 사용자가 지은 이름은 그대로 두고, 이름이 없으면 빈 문자열이다 —
    /// 뷰가 환경 locale 로 「첫 번째 필사」 · 「이름 없는 필사책」 을 보인다. 목록에 없으면(방금 지움 · 늦은 목록) 이름 없는 필사책으로 둔다.
    private func fillHeaderNotebookName(state: inout State, from notebooks: [NotebookSnapshot]) {
        let current = state.currentNotebook
        state.carveDetailState.headerState.notebookName = notebooks.first { $0.id == current }?.name ?? ""
        state.carveDetailState.headerState.isDefaultNotebook = current.isDefault
        state.carveDetailState.headerState.isNotebookNameLoaded = true
    }

    /// iCloud 에서 받은 것이 저장소에 들어올 때마다 지금 필사책을 다시 보고 헤더 이름을 다시 채운다(다른 기기에서 이름을 바꿨을 수 있다).
    /// 구독 시점의 마지막 도착도 한 번 온다(`CloudImportArrivalClient`).
    private func observeNotebookArrivals() -> Effect<Action> {
        .run { [cloudImportArrivals] send in
            for await _ in cloudImportArrivals.arrivals() {
                await send(.checkCurrentNotebook)
            }
        }
        .cancellable(id: CancelID.notebookArrivals, cancelInFlight: true)
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
