//
//  CarveDetailFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Domain
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct CarveDetailFeature: Sendable {
    @ObservableState
    public struct State {
        /// 헤더 상태
        public var headerState: HeaderFeature.State
        /// 장의 본문 행 — 단일 Canvas 의 본문 열 · 장 레이아웃 실측 · 즐겨찾기 · 위젯 · 이미지 저장이 절 본문을 여기서 읽는다.
        public var sentenceWithDrawingState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
        /// 마지막으로 사용한 펜 종류(펜슬 더블탭시 전환용)
        var lastUsedPencil: PKInkingTool.InkType = .pencil

        /// Phase 2 — 장 전체 레이아웃 측정 상태 (설계 §6). 절별 실측이 모이면 `ChapterLayout` 이 완성된다.
        var chapterLayout = ChapterLayoutMeasurement()
        /// 설계 §6-2 입력 게이트. false 인 동안 캔버스의 펜 입력이 막힌다.
        public var isLayoutReady: Bool { chapterLayout.isReady }
        /// 진행 중인 측정 구간의 `os_signpost` ID (`ChapterLayoutSignpost`).
        var layoutSignpostID: UInt64?

        // MARK: 단일 Canvas (설계 §13 Phase 3 — 2.1 부터 필사 화면의 유일한 경로)

        /// 단일 Canvas 상태 — 장 하나를 캔버스 하나로 읽고 쓴다.
        var chapterCanvas = ChapterCanvasFeature.State(chapter: .initialState)
        /// 외부 진입(차트 등)으로 이동할 절 번호. 캔버스가 절 번호로 스크롤한다(`scrollToVerse`).
        var scrollTargetVerse: Int?
        /// 단일 Canvas 의 절 필사 기록 시트 (§8-7 히스토리 UI, B 구조). 롱프레스 → `ChapterCanvasFeature.Delegate.showHistory` 로 연다.
        @Presents var chapterHistory: VerseDrawingHistoryFeature.State?

        // MARK: 즐겨찾기 (시안 N1 · N2 — `CarveDetailFeature+Favorite.swift`)

        /// 지금 장에서 즐겨찾기한 절. 절 메뉴의 항목 문구와 절 번호 아래 별 표시가 읽는다.
        var favoriteVerses: Set<Int> = []
        /// `favoriteVerses` 가 가리키는 장. 장이 바뀐 뒤 늦게 도착한 조회 · 저장 결과를 버리는 기준이다.
        var favoriteChapter: BibleChapter?
        /// 이 화면에서 즐겨찾기를 바꾼 횟수. 바꾸기 전에 시작한 조회가 방금 바꾼 표시를 덮지 않게 한다.
        var favoriteEditCount = 0
        /// 필사 화면 아래 즐겨찾기 결과 안내.
        var favoriteNotice: FavoriteNotice?

        // MARK: 이미지 저장 (시안 G1 · G2 — `CarveDetailFeature+VerseImage.swift`)

        /// 필사 화면 아래 이미지 저장 결과 안내. 즐겨찾기 안내와 같은 자리라 둘 중 하나만 보인다.
        var imageSaveNotice: ImageSaveNotice?
        /// 이미지를 그려 사진에 넣는 중. 같은 요청이 겹치지 않게 한다.
        var isSavingVerseImage = false
        /// 사진 추가 권한이 꺼져 있다는 확인창(시안 G2).
        @Presents var photoPermissionAlert: AlertState<Action.PhotoPermissionAlert>?

        // MARK: 위젯에 추가 (시안 N6 — `CarveDetailFeature+Widget.swift`)

        /// 필사 화면 아래 위젯 결과 안내. 다른 안내와 같은 자리를 나눠 쓴다.
        var widgetNotice: WidgetNotice?
        /// 보관하고 위젯에 담는 중. 같은 요청이 겹치지 않게 한다.
        var isAddingToWidget = false

        /// 성경 문장 출력시 자간 폰트 등 설정
        @Shared(.codableAppStorage(SentenceSetting.appStorageKey)) public var sentenceSetting: SentenceSetting = .initialState
        /// 왼손잡이용 레이아웃 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        /// 설정의 「모든 필사 데이터 삭제」가 올리는 세대. 설정과 이 화면은 서로를 모르므로 공유 값으로 잇는다.
        @Shared(.inMemory(DrawingDataRevision.key)) public var drawingDataRevision: Int = 0
        /// 이 화면이 마지막으로 반영한 세대. 뷰가 트리에서 빠졌다 돌아와도 놓치지 않도록 **값으로** 비교한다.
        public var seenDrawingDataRevision: Int = 0
        
        /// PencilKit 값(`PKInkingTool.InkType` — 헤더 팔레트 · `lastUsedPencil`)을 담아 Sendable 이 아니므로 저장 프로퍼티 대신 계산 프로퍼티다.
        public static var initialState: Self {
            State(
                headerState: .initialState
            )
        }
    }
    @Dependency(\.bibleTextClient) var bibleTextClient
    @Dependency(\.favoriteVerseRepository) var favoriteRepository
    @Dependency(\.date) var date
    @Dependency(\.continuousClock) var clock
    @Dependency(\.verseImageRenderer) var verseImageRenderer
    @Dependency(\.photoLibraryClient) var photoLibraryClient
    @Dependency(\.openURL) var openURL
    @Dependency(\.widgetVerseClient) var widgetVerseClient
    @Dependency(\.drawingEditEnvironment) var drawingEditEnvironment
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        /// 화면 최상단으로 스크롤
        case scrollToTop
        /// 장 본문을 읽었다 — 본문 행 · 레이아웃 측정 · 즐겨찾기를 새로 시작하고 단일 Canvas 에 장을 연다.
        case setSentence([BibleVerse])
        /// 외부 진입(차트 등)이 이동할 절을 정했다.
        case setScrollTarget(BibleVerse)
        /// 단일 Canvas 의 절 필사 기록 시트.
        case chapterHistory(PresentationAction<VerseDrawingHistoryFeature.Action>)
        /// 장의 즐겨찾기를 읽었다. `editCount` 는 조회를 시작할 때의 `favoriteEditCount` 다.
        case favoritesLoaded(chapter: BibleChapter, editCount: Int, verses: Set<Int>)
        /// 즐겨찾기 추가 · 해제의 저장이 끝났다.
        case favoriteChangeFinished(FavoriteChange, failed: Bool)
        /// 즐겨찾기 추가 · 해제를 동기화 저장소에 쓰지 않고 막았다 — 소유가 확인되지 않았다(정책 §12-6 결정 1).
        case favoriteChangeBlocked(FavoriteChange, SyncedWriteBlock)
        /// 다른 화면(즐겨찾기 목록)에서 즐겨찾기가 바뀌었다 — 지금 장의 표시를 다시 읽는다.
        case reloadFavorites
        /// 즐겨찾기 결과 안내를 내린다.
        case favoriteNoticeExpired
        /// 절 이미지를 사진 보관함에 넣는 일이 끝났다.
        case verseImageSaveFinished(VerseImageContent, VerseImageSaveResult)
        /// 이미지 저장 결과 안내를 내린다.
        case imageSaveNoticeExpired
        /// 사진 추가 권한 확인창.
        case photoPermissionAlert(PresentationAction<PhotoPermissionAlert>)
        /// 위젯 표시 지정이 끝났다. `addedToFavorites` 면 즐겨찾기에도 새로 담았다.
        case widgetAddFinished(WidgetDisplayRequest, WidgetAddOutcome)
        /// 위젯 표시 안내를 내린다.
        case widgetNoticeExpired
        
        case view(View)
        case scope(ScopeAction)

        /// 사진 추가 권한 확인창의 버튼.
        public enum PhotoPermissionAlert: Equatable, Sendable {
            /// 「설정 열기」 — 이 앱의 설정 화면을 연다.
            case openSettings
        }
        
        @CasePathable
        public enum View {
            /// 성경 구절 fetch
            case fetchSentence
            /// 밖에서 필사 데이터가 지워졌는지 확인한다 (공유 세대 비교).
            case drawingDataRevisionChanged
            #if DEBUG
            /// HUD가 나타나거나 표시할 진단 값이 바뀌었을 때 콘솔에 기록한다.
            case debugHUDSnapshotChanged(String)
            #endif
            /// 스크롤에 따른 헤더 애니메이션
            case headerAnimation(CGFloat, CGFloat)
            /// 펜을 지우개로 전환
            case switchToEraser
            /// 펜 타입을 이전으로 전환
            case switchToPreviousPenType
            /// 한 손가락 탭 액션: 헤더 펼침/축소
            case tapForHeaderHidden
            /// 두손가락 더블탭 액션: undo
            case twoFingerDoubleTapForUndo
            /// 여러 행의 실측값(밑줄 offset · 소제목 높이 · 캔버스 frame)을 **한 번에** 반영 (Phase 2 — 설계 §6).
            ///
            /// 행마다 액션을 보내면 안 된다 — 액션 하나가 부모 상태를 바꿔 스코프 스토어 전체와 `VStack` 전체 패스를
            /// 다시 돌리므로 행 수의 제곱으로 비용이 늘어난다 (`VerseGeometryCollector` 참조).
            /// 밑줄 offset 을 여기서(행이 아닌 상위에서) 반영하는 것은 ForEachReducer missing element warning 회피이기도 하다.
            case verseGeometryMeasured([SentencesWithDrawingFeature.State.ID: VerseRowGeometry])
            /// 필사 컬럼 폭이 바뀜 (Phase 2 — `ChapterLayout.writingWidth`)
            case layoutHostingChanged(writingWidth: CGFloat)
            /// 앱이 비활성/백그라운드로 감 — 단일 Canvas 의 미저장분을 저장한다 (§8-5, best-effort)
            case appWillResignActive
            /// 디버그 시나리오에서 단일 Canvas의 특정 절로 스크롤
            case scrollToVerse(Int)
            /// 디버그 시나리오에서 다음 장으로 이동
            case moveToNext
            /// 장이 바뀐 뒤 본문을 최상단으로 이동
            case scrollToTop
            /// 절 메뉴의 즐겨찾기 추가 · 해제
            case verseMenuFavoriteTapped
            /// 즐겨찾기 저장 실패 안내의 다시 시도
            case favoriteRetryTapped
            /// 절 메뉴의 이전 필사 보기
            case verseMenuHistoryTapped
            /// 절 메뉴의 이미지 저장
            case verseMenuImageTapped
            /// 이미지 저장 실패 안내의 다시 시도
            case imageSaveRetryTapped
            /// 절 메뉴의 위젯에 표시
            case verseMenuWidgetTapped
            /// 위젯 표시 실패 안내의 다시 시도
            case widgetRetryTapped
            /// 저장 실패 안내의 다시 시도. 큐는 이미 보존돼 있으므로 flush 를 앞당기는 것이다.
            case saveRetryTapped
            /// 조회 실패 안내의 다시 시도. 불러오지 못한 장은 쓸 수 없게 닫혀 있다.
            case loadRetryTapped
            /// 절 메뉴의 「확인이 필요한 필기 N」 — 견주고 고르는 자리로 간다
            case verseMenuDraftsTapped
            /// 절 메뉴의 지우기
            case verseMenuEraseTapped
            /// 절 메뉴 닫기
            case verseMenuDismissed
            /// 절 필사 기록 팝오버 닫기
            case dismissChapterHistory
            /// 하단 팔레트 펼치기
            case expandPalette
        }
    }

    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderFeature()
        }
        Scope(state: \.chapterCanvas,
              action: \.scope.chapterCanvasAction) {
            ChapterCanvasFeature()
        }

        Reduce { state, action in
            switch action {
            #if DEBUG
            case .view(.debugHUDSnapshotChanged(let snapshot)):
                return .run { _ in
                    print("ChapterHUD \(snapshot)")
                }
            #endif
            case .view(.headerAnimation(let previous, let current)):
                return .send(.scope(.headerAction(.headerAnimation(previous, current))))
                
            case .view(.drawingDataRevisionChanged):
                guard state.seenDrawingDataRevision != state.drawingDataRevision else { return .none }
                state.seenDrawingDataRevision = state.drawingDataRevision
                // 즐겨찾기 표시도 함께 지워졌다. 캔버스는 미저장분까지 버리고 DB 에서 다시 합성한다 — 레이아웃은 그대로라 다시 재지 않는다.
                return .merge(
                    .send(.reloadFavorites),
                    .send(.scope(.chapterCanvasAction(.drawingDataCleared)))
                )

            case .view(.fetchSentence):
                let oldChapter = state.headerState.currentTitle
                                
                return .merge(
                    .cancel(id: CancelID.fetchBible(title: oldChapter)),
                    handleFetchSentence(state: &state)
                )
                
            case .setSentence(let sentences):
                // 본문 행만 만든다 — 필사는 단일 Canvas 가 장 단위로 읽는다(아래 `.load`).
                var sentenceState: IdentifiedArrayOf<SentencesWithDrawingFeature.State> = []
                for sentence in sentences {
                    sentenceState.append(SentencesWithDrawingFeature.State(sentence: sentence))
                }
                state.sentenceWithDrawingState = sentenceState
                beginLayoutMeasurement(state: &state, sentences: sentences)
                state.chapterHistory = nil
                let chapter = sentences.first?.title ?? state.headerState.currentTitle
                // 절 번호 아래 즐겨찾기 표시는 본문 컬럼에 그린다.
                let favorites = loadFavorites(state: &state, chapter: chapter)
                // 본문이 확정된 시점에 조회를 시작한다 (§6-4). 레이아웃은 실측이 끝나면 따로 들어간다.
                return .merge(
                    favorites,
                    .send(.scope(.chapterCanvasAction(.load(chapter: chapter, expectedVerseCount: sentences.count))))
                )

            case .scope(.chapterCanvasAction(.drawingsLoaded)):
                // HUD slack 진단(설계 §6-3 `N_saved`) — 캔버스가 방금 읽은 장의 행에서 절별 저장 band 수를 채운다.
                // 캔버스 리듀서(`Scope`)가 먼저 돌았으므로 `loadedDrawings` 는 이번 조회 결과다. 레이아웃 입력이 아니라 다시 짓지 않는다.
                if let loaded = state.chapterCanvas.loadedDrawings {
                    state.chapterLayout.updateSavedBandCounts(Self.savedBandCounts(from: loaded), chapter: state.chapterCanvas.chapter)
                }
                return .none

            case .setScrollTarget(let verse):
                state.scrollTargetVerse = verse.verse
                return .none
                
            case .view(.verseGeometryMeasured(let batch)):
                applyVerseGeometry(state: &state, batch: batch)
                return forwardLayoutToSingleCanvas(state: &state)

            case .view(.layoutHostingChanged(let writingWidth)):
                if state.chapterLayout.setWritingWidth(writingWidth) {
                    rebuildLayoutIfNeeded(state: &state)
                }
                return forwardLayoutToSingleCanvas(state: &state)

            case .view(.appWillResignActive):
                // 단일 Canvas 의 미저장분을 저장한다. 없으면 no-op.
                return .send(.scope(.chapterCanvasAction(.flushPending)))

            case .view(.saveRetryTapped):
                // `flushPending` 이 곧 실패한 저장의 재시도다 (§8-5). 사용자가 기다리지 않고 지금 시도하게 한다.
                return .send(.scope(.chapterCanvasAction(.flushPending)))

            case .view(.loadRetryTapped):
                return .send(.scope(.chapterCanvasAction(.retryLoad)))

            case .view(.scrollToVerse(let verse)):
                return .send(.scope(.chapterCanvasAction(.scrollToVerse(verse))))

            case .view(.moveToNext):
                return .send(.scope(.headerAction(.view(.moveToNext))))

            case .view(.scrollToTop):
                return .send(.scrollToTop)

            case .view(.verseMenuFavoriteTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuFavoriteTapped)))

            case .scope(.chapterCanvasAction(.delegate(.favoriteToggled(let verse, let ink)))):
                return toggleFavorite(state: &state, verse: verse, ink: ink)

            case .favoritesLoaded, .favoriteChangeFinished, .favoriteChangeBlocked, .reloadFavorites, .favoriteNoticeExpired, .view(.favoriteRetryTapped):
                return reduceFavorite(state: &state, action: action)

            case .view(.verseMenuHistoryTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuHistoryTapped)))

            case .view(.verseMenuImageTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuImageTapped)))

            case .scope(.chapterCanvasAction(.delegate(.imageSaveRequested(let handwriting)))):
                return saveVerseImage(state: &state, handwriting: handwriting)

            case .verseImageSaveFinished, .imageSaveNoticeExpired, .photoPermissionAlert, .view(.imageSaveRetryTapped):
                return reduceVerseImage(state: &state, action: action)

            case .view(.verseMenuWidgetTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuWidgetTapped)))

            case let .scope(.chapterCanvasAction(.delegate(.widgetRequested(verse, ink)))):
                return addVerseToWidget(state: &state, verse: verse, ink: ink)

            case .widgetAddFinished, .widgetNoticeExpired, .view(.widgetRetryTapped):
                return reduceWidget(state: &state, action: action)

            case .view(.verseMenuDraftsTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuDraftsTapped)))

            case .view(.verseMenuEraseTapped):
                return .send(.scope(.chapterCanvasAction(.verseMenuEraseTapped)))

            case .view(.verseMenuDismissed):
                return .send(.scope(.chapterCanvasAction(.verseMenuDismissed)))

            case .view(.dismissChapterHistory):
                return .send(.chapterHistory(.dismiss))

            case .view(.expandPalette):
                return .send(.scope(.headerAction(.view(.expandPalette))))

            case .scope(.chapterCanvasAction(.delegate(.showHistory(let verse)))):
                var history = VerseDrawingHistoryFeature.State(title: state.chapterCanvas.chapter, verse: verse)
                history.anchorFrame = state.chapterCanvas.historyAnchorFrame
                state.chapterHistory = history
                return .none

            case .chapterHistory(.presented(.setPresentDrawing(let drawing))):
                // §8-7 복원 흐름 — ② isPresent 이전은 시트가 이미 DB 에 반영했다. ③ mutation 없이 다시 합성하며,
                // 그 안에서 ① 미저장분이 먼저 저장된다 (rowID 주소지정이라 이전 활성 행의 변경도 유실되지 않는다).
                guard state.chapterHistory != nil else { return .none }
                state.chapterHistory = nil
                return .send(.scope(.chapterCanvasAction(
                    .verseRowRestored(verse: drawing.verse, rowID: drawing.rowID)
                )))

            case .scope(.headerAction(.palatteAction(.view(.undo)))):
                // 팔레트의 undo/redo 는 늘 캔버스(`canvas.undoManager`)가 처리한다.
                return .send(.scope(.chapterCanvasAction(.undoTapped)))

            case .scope(.headerAction(.palatteAction(.view(.redo)))):
                return .send(.scope(.chapterCanvasAction(.redoTapped)))

            case .scrollToTop:
                return scrollToTop(state: &state)

            case .view(.switchToEraser):
                // monoline을 지우개로 사용
                state.lastUsedPencil = state.headerState.palatteSetting.pencilConfig.pencilType
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(.monoline))))))
                
            case .view(.switchToPreviousPenType):
                // 지우개인 경우 기본 펜으로
                return .send(
                    .scope(.headerAction(.palatteAction(.view(.setPencilType(state.lastUsedPencil)))))
                )
                
            case .scope(.headerAction(.palatteAction(.view(.setPencilType(let penType))))):
                guard penType != .monoline,
                      penType != state.lastUsedPencil
                else { return .none }
                
                state.lastUsedPencil = penType
                return .none

            case .view(.tapForHeaderHidden):
                return .send(.scope(.headerAction(.toggleCompact)))

            case .view(.twoFingerDoubleTapForUndo):
                Log.debug("두손가락 탭")
                return .send(.scope(.headerAction(.palatteAction(.view(.undo)))))

            default: return .none
            }
        }
        .forEach(\.sentenceWithDrawingState,
                  action: \.scope.sentenceWithDrawingAction) {
            SentencesWithDrawingFeature()
        }
        .ifLet(\.$chapterHistory, action: \.chapterHistory) {
            VerseDrawingHistoryFeature()
        }
        .ifLet(\.$photoPermissionAlert, action: \.photoPermissionAlert)
    }
}


extension CarveDetailFeature {
    @CasePathable
    public enum ScopeAction {
        case sentenceWithDrawingAction(IdentifiedActionOf<SentencesWithDrawingFeature>)
        case headerAction(HeaderFeature.Action)
        /// Phase 3 — 단일 Canvas
        case chapterCanvasAction(ChapterCanvasFeature.Action)
    }

    /// 비동기 작업 취소용 작업
    enum CancelID: Hashable {
        /// 성경 불러올떄
        case fetchBible(title: BibleChapter)
        /// 장의 즐겨찾기 조회
        case loadFavorites
        /// 즐겨찾기 결과 안내의 자동 닫힘
        case favoriteNotice
        /// 이미지 저장 결과 안내의 자동 닫힘
        case imageSaveNotice
        /// 위젯 표시 안내의 자동 닫힘
        case widgetNotice
    }
}

extension CarveDetailFeature {
    // MARK: - Phase 2 — 장 레이아웃 측정 (설계 §6)

    /// 새 장의 본문이 확정된 시점에 측정을 시작한다. 이전 장의 실측값은 전부 버린다.
    ///
    /// `expectedVerseCount` 는 여기서 확정된 절 개수이며(§6-4), 게이트는 이 값과 완성된 레이아웃의 절 수를 비교한다.
    /// 절별 저장 band 수(HUD slack 진단)는 아직 모른다 — 캔버스가 장을 읽은 뒤(`drawingsLoaded`) 채운다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - sentences: fetch 된 본문.
    private func beginLayoutMeasurement(state: inout State, sentences: [BibleVerse]) {
        let chapter = sentences.first?.title ?? state.headerState.currentTitle
        state.chapterLayout.begin(
            chapter: chapter,
            verses: sentences.map(\.verse),
            savedBandCounts: [:],
            now: ContinuousClock().now
        )
        state.layoutSignpostID = ChapterLayoutSignpost.beginMeasure(chapter: chapter, verseCount: sentences.count)
        // 폭은 장이 바뀌어도 그대로이므로 이미 알고 있으면 곧바로 계산 조건에 포함된다.
        rebuildLayoutIfNeeded(state: &state)
    }

    /// 행들의 실측값을 한 번에 반영한다.
    ///
    /// 이전 장의 행에서 늦게 도착한 값은 id 조회에 실패해 버려진다 (설계 §6-4 의 요청 취소).
    /// 레이아웃 재계산은 배치 전체를 반영한 뒤 **한 번만** 한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - batch: 행 id → 실측값.
    private func applyVerseGeometry(state: inout State, batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry]) {
        var layoutInputChanged = false
        for (id, geometry) in batch {
            guard var row = state.sentenceWithDrawingState[id: id] else { continue }
            let verse = row.sentence.verse

            if let offsets = geometry.underlineOffsets {
                // 밑줄은 캔버스 영역 안에서 1절의 상단 여백만큼 내려 그려지므로, 레이아웃 anchor 도 같은 값을 더한다.
                let anchors = offsets.map { $0 + ChapterLayoutHosting.topPadding(forVerse: verse) }
                if row.sentenceState.underlineOffsets != offsets {
                    row.sentenceState.underlineOffsets = offsets
                    state.sentenceWithDrawingState[id: id] = row
                }
                if state.chapterLayout.recordText(verse: verse, underlineAnchors: anchors) {
                    layoutInputChanged = true
                }
            }
            if let height = geometry.titleHeight,
               state.chapterLayout.recordTitleHeight(verse: verse, height: height) {
                layoutInputChanged = true
            }
            // 행 frame 은 원점만 쓰인다 (`columnOrigin` · Δ 의 topDelta). 검증 전용이라 재계산 조건에 넣지 않는다.
            if let frame = geometry.rowFrame {
                state.chapterLayout.recordRowFrame(verse: verse, frame: frame)
            }
            // 행 안 캔버스 영역의 **높이**는 레이아웃 입력이다 (R13 — `VerseLayoutInput.measuredHeight`).
            // 빌더의 `줄 수 × lineSpace` 예측이 실기기에서 절당 0.5pt 씩 어긋나 누적됐으므로 실측을 쓴다.
            // 따라서 재계산 조건에 **포함한다** — 예측으로 지은 레이아웃이 실측이 도착하면 다시 지어진다.
            if let frame = geometry.canvasFrameInRow,
               state.chapterLayout.recordCanvasFrameInRow(verse: verse, frame: frame) {
                layoutInputChanged = true
            }
        }
        if layoutInputChanged {
            rebuildLayoutIfNeeded(state: &state)
        }
    }

    /// 입력이 전부 모였으면 레이아웃을 (재)계산하고 계측을 남긴다.
    /// - Parameter state: Feature 상태.
    private func rebuildLayoutIfNeeded(state: inout State) {
        let wasBuilt = state.chapterLayout.buildCount > 0
        guard let layout = state.chapterLayout.rebuildIfComplete(
            setting: state.sentenceSetting,
            isLeftHanded: state.isLeftHanded,
            metrics: ChapterLayoutHosting.metrics,
            now: ContinuousClock().now
        ) else { return }

        if wasBuilt {
            ChapterLayoutSignpost.rebuildEvent(layout: layout, buildCount: state.chapterLayout.buildCount)
            return
        }
        if let signpostID = state.layoutSignpostID, let duration = state.chapterLayout.firstBuildDuration {
            ChapterLayoutSignpost.endMeasure(rawID: signpostID, layout: layout, duration: duration)
            state.layoutSignpostID = nil
            Log.info("ChapterLayout 완성", "\(layout.chapter.title.rawValue).\(layout.chapter.chapter)",
                     "\(layout.regions.count)절", "H=\(layout.totalHeight)", "\(duration)")
        }
    }

    /// 단일 Canvas 가 읽은 장의 행에서 절별 저장 band 수(설계 §6-3 의 `N_saved`)를 뽑는다 — HUD slack 진단 전용.
    ///
    /// 절마다 대표 행(`DrawingRepresentativeRule` — 캔버스가 합성하는 그 행)만 본다. metadata 가 없는 행(v1 · v2 · metadata 를 잃은 v3)은 빠진다.
    /// - Parameter snapshots: `ChapterCanvasFeature.State.loadedDrawings` — 히스토리 행 포함.
    /// - Returns: 절 → band 수. 부작용 없음.
    static func savedBandCounts(from snapshots: [VerseDrawingSnapshot]) -> [Int: Int] {
        snapshots.representativesByVerse().compactMapValues { $0.metadata?.savedBandCount }
    }

    /// 성경 본문을 읽어 `setSentence` 로 넘긴다. 필사는 단일 Canvas 가 `setSentence` 뒤 장 단위로 읽는다.
    /// - Parameter state: Feature 상태(지금 장).
    /// - Returns: 본문을 읽는 효과. 장이 바뀌면 이전 장의 읽기는 취소된다. 실패하면 로그만 남긴다.
    private func handleFetchSentence(state: inout State) -> Effect<Action> {
        let title = state.headerState.currentTitle

        return .run { send in
            do {
                let sentences = try bibleTextClient.fetch(chapter: title)
                try Task.checkCancellation()
                await send(.setSentence(sentences))
            } catch {
                Log.error("Fetch Sentence Error")
            }
        }
        .cancellable(id: CancelID.fetchBible(title: title), cancelInFlight: true)
    }


    /// 외부 진입으로 정한 절(없으면 첫 절)로 캔버스를 스크롤한다.
    private func scrollToTop(state: inout State) -> Effect<Action> {
        let verse = state.scrollTargetVerse ?? state.sentenceWithDrawingState.first?.sentence.verse
        state.scrollTargetVerse = nil
        guard let verse else { return .none }
        return .send(.scope(.chapterCanvasAction(.scrollToVerse(verse))))
    }

    /// Phase 3 — 완성된 `ChapterLayout` · `columnOrigin` · Δ 안전망 판정을 단일 Canvas 에 넘긴다. 값이 바뀐 것만 보낸다.
    ///
    /// `columnOrigin` 의 y 는 0 이다 — 헤더는 `contentInset.top` 으로 비우므로 콘텐츠 좌표는 헤더와 무관하다.
    /// Δ 안전망(설계 §14 — D9 R13)은 여기서 판정을 넘겨 캔버스의 새 획 입력만 닫는다.
    private func forwardLayoutToSingleCanvas(state: inout State) -> Effect<Action> {
        guard let layout = state.chapterLayout.layout else { return .none }
        var effects: [Effect<Action>] = []
        if let origin = state.chapterLayout.columnOrigin,
           origin != state.chapterCanvas.columnOrigin, origin != state.chapterCanvas.pendingColumnOrigin {
            effects.append(.send(.scope(.chapterCanvasAction(.columnOriginChanged(origin)))))
        }
        if layout != state.chapterCanvas.layout && layout != state.chapterCanvas.pendingLayout {
            effects.append(.send(.scope(.chapterCanvasAction(.layoutCompleted(layout)))))
        }
        let verdict = state.chapterLayout.layoutDeltaVerdict
        if verdict != state.chapterCanvas.layoutDelta {
            effects.append(.send(.scope(.chapterCanvasAction(.layoutDeltaEvaluated(verdict)))))
        }
        return effects.isEmpty ? .none : .merge(effects)
    }
}
