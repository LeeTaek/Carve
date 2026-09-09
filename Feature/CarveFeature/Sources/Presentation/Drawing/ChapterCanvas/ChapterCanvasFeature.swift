//
//  ChapterCanvasFeature.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import CoreGraphics
import Domain
import Foundation

import ComposableArchitecture

// MARK: - 편집 계약 DTO (설계 §5 · §8-1)

/// 편집 종료 시점 스냅샷 (PencilKit 타입 없음).
public struct CanvasEditSnapshot: Equatable, Sendable {
    /// 편집 직후 캔버스 content 좌표 drawing.
    let drawingData: Data
    /// 변경 영역. 디버그 표시용이며 저장 계산에는 쓰지 않는다.
    let dirtyBounds: CGRect?
    let reason: EditReason
    /// 이 편집이 이루어진 캔버스 내용의 **세대** — 편집 당시 캔버스가 표시하던 `renderedRevision`.
    ///
    /// 장 전환이나 재합성 뒤에 도착한 편집을 새 내용 기준으로 계산하면 다른 장에 저장되거나(오저장) 큐가 막힌다.
    /// Feature 는 이 값으로 편집을 자기 세대의 문맥(현재 또는 `retiredSession`)에서 계산하고, 어느 쪽도 아니면 버린다 (rev.17).
    let generation: Int
}

public enum EditReason: Equatable, Sendable { case ink, erase, undo, redo }

/// 저장 중 도착한 최신 편집을 보호하기 위해 revision 과 장을 함께 보관한다 (§8-3).
struct PendingDrawingMutation: Equatable, Sendable {
    let revision: Int
    /// 이 명령이 속한 장. 장 전환 직후에도 이전 장의 미저장분을 올바른 장에 저장하기 위함이다 (§8-5).
    let chapter: BibleChapter
    let mutation: VerseDrawingMutation
}

enum SaveStatus: Equatable, Sendable {
    case idle
    case saving(revision: Int)
    case failed(revision: Int, retryCount: Int)
}

/// 조회 실패. `Error` 는 Equatable 이 아니라 메시지만 옮긴다.
public struct DrawingLoadFailure: Error, Equatable, Sendable {
    let message: String
}

/// 편집을 계산하는 문맥 — **합성 시점**의 레이아웃·`columnOrigin`·활성 행·소유권·기준 drawing.
///
/// 큐에 남은 편집은 캔버스가 그 편집 당시 표시하던 내용(세대) 기준으로 계산해야 한다. 장이 바뀌면 현재 상태는 새 장으로
/// 덮이므로, 이전 장의 문맥은 `retiredSession` 으로 물려 두어 늦게 도착한 편집(코덱 진행 중 · trailing 보고)을 자기 장으로 저장한다.
struct EditSession: Equatable, Sendable {
    let generation: Int
    let chapter: BibleChapter
    let layout: ChapterLayout
    let columnOrigin: CGPoint
    var activeRowIDs: [Int: BibleDrawingRowID]
    var ownership: OwnershipSnapshot
    var baselineData: Data
}

// MARK: - Feature

/// 장(chapter)당 하나인 단일 Canvas 의 상태·저장 orchestration (설계 §4).
///
/// **PencilKit 타입을 모른다** (P9). 캔버스 내용은 `Data`, 소유권은 `OwnershipSnapshot`, 저장은 `VerseDrawingMutation` 이다.
///
/// ## 흐름 (§8-8)
///
/// ```
/// load → drawingsLoaded ┐
///        layoutCompleted ┴→ composeIfReady (§6-4 게이트) → renderedData / ownership / activeRowIDs
/// editBegan → isEditing (layout · columnOrigin · 복원 재합성 보류)
/// editEnded(generation) → 세대 확인 → editQueue → 코덱 (한 번에 하나: 다음 편집의 before = 이전 편집의 결과)
///   → mutationsPrepared → ownership 승계 · 신규 rowID 예약 · pendingMutations 에 rowID 키로 coalescing
///   → 저장은 동시에 하나 (saveStatus) → saveFinished → revision 이 같은 항목만 제거 → 다음 batch
/// 실패 → 화면 유지 + 큐 보존 + 다음 편집/flush/장 전환 에서 재시도 (§8-4)
/// ```
///
/// ## 재합성 규칙
///
/// 레이아웃·`columnOrigin` 변경과 히스토리 복원은 **미저장분을 먼저 저장한 뒤 DB 에서 다시 합성**한다 (`reloadAfterSettling`).
/// 그 사이 저장이나 재조회가 실패하면 입력을 영원히 잠그는 대신, **마지막으로 알고 있는 DB 내용(`loadedDrawings`) 위에
/// 미저장분(`pendingMutations`)을 겹쳐** 지금 합성한다. 합성은 언제나 `DB 내용 ⊕ 미저장분` 이므로 잉크가 화면에서 사라지지 않고,
/// 성공한 저장은 `loadedDrawings` 에도 반영해 두 값의 합이 항상 현재 내용이 되게 한다.
@Reducer
public struct ChapterCanvasFeature {
    @ObservableState
    public struct State: Equatable {
        var chapter: BibleChapter

        // §6-4 — 도착 순서가 보장되지 않는 두 입력과 게이트
        var expectedVerseCount: Int?
        var layout: ChapterLayout?
        /// 마지막으로 알고 있는 이 장의 DB 내용. 성공한 저장을 겹쳐 두므로 재조회 없이도 현재 내용의 근거가 된다.
        var loadedDrawings: [VerseDrawingSnapshot]?
        var loadRequestID: UUID?
        var loadFailure: DrawingLoadFailure?
        /// 캔버스 content 좌표 = layout 좌표 + columnOrigin (§5). 값은 호스팅이 준다.
        var columnOrigin: CGPoint = .zero
        /// 예측 좌표와 실제 렌더의 Δ 안전망 판정 (설계 §14 — D9 R13). `CarveDetailFeature` 가 실측에서 계산해 넘긴다.
        /// **합성·저장에는 관여하지 않는다** — `isDrawingInputEnabled` 하나만 읽는다.
        var layoutDelta: LayoutDeltaVerdict?

        // 합성 결과
        var renderedData: Data?
        /// 캔버스 내용의 세대. 합성마다, 그리고 **장 진입마다** 오른다 — 뷰는 이 값이 바뀔 때만 캔버스를 교체한다.
        var renderedRevision = 0
        /// 합성에 쓴 레이아웃·`columnOrigin`. 큐의 편집은 이 기준으로 계산한다 (`layout`·`columnOrigin` 은 다음 합성용 최신값).
        var renderedLayout: ChapterLayout?
        var renderedColumnOrigin: CGPoint = .zero
        var ownership: OwnershipSnapshot?
        var activeRowIDs: [Int: BibleDrawingRowID] = [:]
        var layoutMismatchVerses: Set<Int> = []
        var legacyVerses: Set<Int> = []
        /// 디코드하지 못한 행의 절. 활성 행에서 빠져 있어 다음 편집은 새 행으로 간다 (`DrawingCodec`).
        var undecodableVerses: Set<Int> = []
        /// 이번 합성에서 legacy 로 배치된 잉크의 content 좌표 bounds (D9 진단, HUD `legInk`).
        /// `columnOrigin` 이 결과 좌표까지 실제로 갔는지를 상태가 아니라 **좌표**로 확인하는 값이다.
        var legacyInkBounds: CGRect?
        /// 마지막 편집 스냅샷의 `dirtyBounds`(content 좌표)와 그 상단이 속한 절. 디버그 오버레이 표시용이며 저장 계산에 쓰지 않는다.
        var lastDirtyBounds: CGRect?
        var lastEditedVerse: Int?

        // §8-1 편집 계약
        var editRevision = 0
        var persistedRevision = 0
        var isEditing = false
        /// 편집 중 도착한 변경. pencil-up 뒤에 한 번에 적용한다 — 획 도중 재합성하면 획이 사라진다.
        var pendingLayout: ChapterLayout?
        var pendingColumnOrigin: CGPoint?
        var pendingReload = false
        /// pencil-up 순서의 처리 대기 편집. 코덱은 한 번에 하나만 돈다.
        var editQueue: [QueuedEdit] = []
        var isPreparingEdit = false
        /// 코덱이 마지막으로 처리한 캔버스 내용 — 다음 편집의 before.
        var baselineData: Data?
        /// 장 전환으로 물러난 이전 장의 편집 문맥. 늦게 도착한 이전 장 편집을 자기 장 기준으로 계산해 저장한다.
        var retiredSession: EditSession?

        // §8-3 저장 대기열
        var pendingMutations: [BibleDrawingRowID: PendingDrawingMutation] = [:]
        var saveStatus: SaveStatus = .idle
        /// 지금 저장 중인 batch 의 rowID → revision. 성공 시 같은 revision 인 항목만 제거한다 (§8-3 5번).
        var inFlightBatch: [BibleDrawingRowID: Int] = [:]
        /// 지금 저장 중인 batch 의 내용과 장. 성공하면 `loadedDrawings` 에 겹쳐 DB 내용을 따라가게 한다.
        var inFlightMutations: [VerseDrawingMutation] = []
        var inFlightChapter: BibleChapter?
        /// 미저장분이 전부 저장되면 DB 에서 다시 합성한다 (레이아웃 변경 · 복원).
        var reloadWhenSettled = false
        var isReloading = false

        // UI-2 지우기 (보관 후 초기화)

        /// 진행 중이거나 실패한 지우기 작업. 진행 중에는 입력·중복 지우기·재합성을 막는다.
        var eraseTask: VerseEraseTask?
        /// 지우기 확인창(권·장·절 포함)과 실패 안내를 함께 쓰는 알림.
        @Presents var eraseAlert: AlertState<Action.EraseAlert>?

        /// 헤더 팔레트가 읽는 undo/redo 가능 여부 — `PencilPalatteFeature` 와 같은 in-memory 키를 공유한다.
        @Shared(.inMemory("canUndo")) var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) var canRedo: Bool = false
        /// 뷰가 캔버스의 undoManager 에 undo/redo 를 수행하도록 하는 요청 카운터.
        var undoRequestVersion = 0
        var redoRequestVersion = 0
        /// 특정 절로 스크롤 요청 (차트 등 외부 진입). 토큰이 바뀔 때만 뷰가 수행한다.
        var scrollRequest: ScrollRequest?
        /// 스크롤 요청 토큰. **장이 바뀌어도 초기화하지 않는다** — 뷰가 마지막으로 수행한 토큰과 겹치면 요청이 무시된다.
        var scrollRequestToken = 0

        struct QueuedEdit: Equatable, Sendable {
            let revision: Int
            let snapshot: CanvasEditSnapshot
        }

        struct ScrollRequest: Equatable, Sendable {
            let verse: Int
            let token: Int
        }

        init(chapter: BibleChapter) {
            self.chapter = chapter
        }

        var isComposed: Bool { renderedData != nil }
        /// §6-2 입력 게이트 — 합성이 끝났고, 다시 합성하지도 지우지도 않는 중일 때만 입력을 받는다.
        var isInputEnabled: Bool { isComposed && !isReloading && !isErasing }
        /// 지우기가 실제로 도는 중인가. `.failed` 는 **포함하지 않는다** — 실패하면 잠금을 풀고 필기를 그대로 쓰게 둔다.
        var isErasing: Bool {
            switch eraseTask?.phase {
            case .flushing, .archiving: true
            case .failed, nil: false
            }
        }
        /// **새 획 입력만** 여는 게이트 (설계 §14 — D9 안전망). 캔버스의 `drawingGestureRecognizer` 하나가 읽는다.
        ///
        /// 레이아웃이 실제 렌더와 한 줄 이상 어긋나면(`LayoutDeltaVerdict.blocksInput`) 그 상태의 새 획은
        /// 잘못된 절에 귀속되므로 받지 않는다. **합성·표시·저장·flush·복원은 그대로 돈다** — 그 경로들은
        /// `isComposed` / `isReloading` / `isFullyPersisted` 만 보므로 이 값과 무관하다.
        /// 여기서 게이트를 `isReady`(§6-4 합성 게이트)로 올리면 기존 잉크가 안 보이거나 미저장분이 유실될 수 있다.
        var isDrawingInputEnabled: Bool { isInputEnabled && layoutDelta?.blocksInput != true }
        /// 미저장 여부의 판정 기준 (§8-3). `persistedRevision` 이 아니라 큐가 비었는가로 본다.
        var isFullyPersisted: Bool {
            pendingMutations.isEmpty && saveStatus == .idle && editQueue.isEmpty && !isPreparingEdit
        }

        /// 현재 세대의 편집 문맥. 합성 전에는 없다.
        var currentSession: EditSession? {
            guard renderedData != nil,
                  let layout = renderedLayout,
                  let ownership,
                  let baselineData else { return nil }
            return EditSession(
                generation: renderedRevision, chapter: chapter, layout: layout, columnOrigin: renderedColumnOrigin,
                activeRowIDs: activeRowIDs, ownership: ownership, baselineData: baselineData
            )
        }

        /// 세대 번호가 가리키는 편집 문맥. 현재 세대도 물러난 세대도 아니면 nil — 그 편집은 계산할 기준이 없다.
        func session(for generation: Int) -> EditSession? {
            if generation == renderedRevision { return currentSession }
            if let retiredSession, retiredSession.generation == generation { return retiredSession }
            return nil
        }
    }

    public enum Action: Equatable {
        /// 장 진입. 이전 장의 미저장분은 버리지 않고 자기 장으로 저장된다.
        case load(chapter: BibleChapter, expectedVerseCount: Int)
        case drawingsLoaded(requestID: UUID, Result<[VerseDrawingSnapshot], DrawingLoadFailure>)
        case layoutCompleted(ChapterLayout)
        case columnOriginChanged(CGPoint)
        /// 예측 좌표와 실제 렌더의 Δ 안전망 판정이 갱신됐다 (§14 — D9 R13). 새 입력만 좌우한다.
        case layoutDeltaEvaluated(LayoutDeltaVerdict?)

        case editBegan
        case editEnded(CanvasEditSnapshot)
        /// 도구는 댔지만 drawing 이 바뀌지 않은 경우 (탭 등). 보류된 변경을 적용한다.
        case editCancelled
        case mutationsPrepared(revision: Int, DrawingEditResult)
        case saveFinished(revision: Int, failure: DrawingRepositoryError?)
        /// 장 전환 · 백그라운드 진입 시 대기열 저장 (§8-5). 실패했던 저장의 재시도이기도 하다.
        case flushPending
        /// 히스토리에서 다른 회차를 선택해 `isPresent` 가 바뀐 뒤. mutation 을 만들지 않고 다시 합성한다 (§8-7).
        case verseRowRestored(verse: Int, rowID: BibleDrawingRowID)
        case undoStateChanged(canUndo: Bool, canRedo: Bool)
        case undoTapped
        case redoTapped
        case scrollToVerse(Int)
        /// 캔버스를 길게 눌러 그 자리(content 좌표)의 절 필사 기록을 요청 (§8-7 히스토리 UI, B 구조).
        case historyRequested(at: CGPoint)
        /// 롱프레스 메뉴의 "지우기" — 그 자리(content 좌표)의 절을 보관 후 초기화한다 (UI-2). 먼저 확인창을 띄운다.
        case eraseRequested(at: CGPoint)
        case eraseAlert(PresentationAction<EraseAlert>)
        /// 보관+초기화 트랜잭션의 결과. 성공하면 `outcome`, 실패하면 `failure` 가 온다.
        case eraseFinished(outcome: VerseDrawingArchiveOutcome?, failure: DrawingRepositoryError?)
        case delegate(Delegate)

        /// 지우기 확인창·실패 안내의 버튼.
        public enum EraseAlert: Equatable, Sendable {
            /// 확인창에서 "지우기" 를 눌렀다.
            case confirm(verse: Int)
            /// 실패 안내에서 "다시 시도" 를 눌렀다. **같은 보관 rowID 로** 다시 시도한다.
            case retry
        }

        /// 부모(`CarveDetailFeature`)가 처리하는 사건.
        public enum Delegate: Equatable, Sendable {
            /// 이 절의 필사 기록 시트를 열어 달라.
            case showHistory(verse: Int)
        }
    }

    @Dependency(\.drawingCodec) var codec
    @Dependency(\.drawingRepository) var repository
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load(let chapter, let expectedVerseCount):
                return beginLoad(state: &state, chapter: chapter, expectedVerseCount: expectedVerseCount)

            case .drawingsLoaded(let requestID, let result):
                return finishLoad(state: &state, requestID: requestID, result: result)

            case .layoutCompleted(let layout):
                if state.isEditing {
                    state.pendingLayout = layout
                    return .none
                }
                return applyLayout(state: &state, layout: layout)

            case .columnOriginChanged(let origin):
                if state.isEditing {
                    // 획 도중 재합성하면 그 획이 화면에서 사라지고, 큐에 남은 편집이 새 기준으로 계산된다. pencil-up 뒤로 미룬다.
                    state.pendingColumnOrigin = origin == state.columnOrigin ? nil : origin
                    return .none
                }
                return applyColumnOrigin(state: &state, origin: origin)

            case .layoutDeltaEvaluated(let verdict):
                // 편집 중에도 곧바로 반영한다 — 이 값은 재합성을 일으키지 않고 새 획 입력만 좌우하므로
                // 그리던 획이 사라지지 않는다 (`layoutCompleted` / `columnOriginChanged` 와 다른 점).
                let previous = state.layoutDelta
                state.layoutDelta = verdict
                LayoutDeltaVerdict.logIfNoteworthy(previous: previous, current: verdict, chapter: state.chapter)
                return .none

            case .editBegan:
                state.isEditing = true
                return .none

            case .editCancelled:
                state.isEditing = false
                return applyDeferredChanges(state: &state)

            case .editEnded(let snapshot):
                state.isEditing = false
                if state.eraseTask?.phase == .archiving {
                    // 보관 트랜잭션이 도는 중에 도착한 편집. 이 편집의 before 는 지우기 **이전** 내용이므로 받아들이면
                    // 그 절의 획을 활성 행에 다시 써 사용자가 확인한 지우기를 되돌린다. 입력은 확인 시점부터 잠겨 있으므로
                    // 여기 오는 것은 그 사이(≈트랜잭션 한 번)의 늦은 보고뿐이다. 세대가 맞지 않는 편집과 같이 버린다.
                    Log.error("단일 Canvas — 지우기(보관+초기화) 중 도착한 편집을 버린다",
                              "generation=\(snapshot.generation)", "verse=\(state.eraseTask?.verse ?? -1)")
                    return .none
                }
                var effects: [Effect<Action>] = []
                if let session = state.session(for: snapshot.generation) {
                    state.editRevision += 1
                    state.editQueue.append(State.QueuedEdit(revision: state.editRevision, snapshot: snapshot))
                    state.lastDirtyBounds = snapshot.dirtyBounds
                    state.lastEditedVerse = snapshot.dirtyBounds.flatMap { bounds in
                        session.layout.verse(containing: CGPoint(
                            x: min(max(bounds.minX - session.columnOrigin.x, 0), session.layout.writingWidth),
                            y: bounds.minY - session.columnOrigin.y
                        ))
                    }
                    effects.append(drainEditQueue(state: &state))
                } else {
                    // 계산할 기준이 없는 세대 — 장이 두 번 바뀌었거나 재합성 뒤에 도착했다. 새 내용 기준으로 처리하면 오저장이다.
                    Log.error("단일 Canvas — 세대가 맞지 않는 편집을 버린다",
                              "generation=\(snapshot.generation)", "rendered=\(state.renderedRevision)")
                }
                effects.append(applyDeferredChanges(state: &state))
                return .merge(effects)

            case .mutationsPrepared(let revision, let result):
                return finishEdit(state: &state, revision: revision, result: result)

            case .saveFinished(let revision, let failure):
                return finishSave(state: &state, revision: revision, failure: failure)

            case .flushPending:
                return startSaveIfPossible(state: &state, allowRetry: true)

            case .verseRowRestored:
                // isPresent 이전은 호출부(히스토리 시트)가 이미 DB 에 반영했다. 여기서는 mutation 없이 다시 합성만 한다.
                if state.isEditing {
                    state.pendingReload = true
                    return .none
                }
                return reloadAfterSettling(state: &state)

            case .undoStateChanged(let canUndo, let canRedo):
                state.$canUndo.withLock { $0 = canUndo }
                state.$canRedo.withLock { $0 = canRedo }
                return .none

            case .undoTapped:
                guard state.isInputEnabled, state.canUndo else { return .none }
                state.undoRequestVersion += 1
                return .none

            case .redoTapped:
                guard state.isInputEnabled, state.canRedo else { return .none }
                state.redoRequestVersion += 1
                return .none

            case .scrollToVerse(let verse):
                state.scrollRequestToken += 1
                state.scrollRequest = State.ScrollRequest(verse: verse, token: state.scrollRequestToken)
                return .none

            case .historyRequested(let point):
                guard let verse = Self.verse(at: point, state: state) else { return .none }
                return .send(.delegate(.showHistory(verse: verse)))

            case .eraseRequested(let point):
                // 진행 중이거나 실패해 안내 중인 지우기가 있으면 새로 열지 않는다 (중복 지우기 방지).
                guard state.eraseTask == nil, let verse = Self.verse(at: point, state: state) else { return .none }
                state.eraseAlert = Self.confirmEraseAlert(chapter: state.chapter, verse: verse)
                return .none

            case .eraseAlert(.presented(.confirm(let verse))):
                return beginErase(state: &state, verse: verse)

            case .eraseAlert(.presented(.retry)):
                return retryErase(state: &state)

            case .eraseAlert(.dismiss):
                // 실패 안내를 닫으면 그 작업은 끝난다 — 필기는 그대로 남고, 다시 지우려면 메뉴에서 새로 시작한다.
                if state.eraseTask?.phase == .failed { state.eraseTask = nil }
                return .none

            case .eraseFinished(let outcome, let failure):
                return finishErase(state: &state, outcome: outcome, failure: failure)

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$eraseAlert, action: \.eraseAlert)
    }

    /// content 좌표가 가리키는 절. 표시 중인 레이아웃(합성 시점 값)으로 찾고, 텍스트 쪽(컬럼 왼쪽)을 눌러도
    /// 같은 행이 되도록 x 만 컬럼 안으로 당긴다 (§20-11). 합성 전이거나 세로로 벗어나면 nil.
    static func verse(at point: CGPoint, state: State) -> Int? {
        guard state.isInputEnabled, let layout = state.renderedLayout else { return nil }
        let origin = state.renderedColumnOrigin
        let layoutPoint = CGPoint(
            x: min(max(point.x - origin.x, 0), layout.writingWidth),
            y: point.y - origin.y
        )
        return layout.verse(containing: layoutPoint)
    }
}

// MARK: - 조회 · 합성 (§6-4)

extension ChapterCanvasFeature {
    private func beginLoad(state: inout State, chapter: BibleChapter, expectedVerseCount: Int) -> Effect<Action> {
        // 이전 장의 편집 문맥을 물려 둔다 — 큐·코덱·trailing 보고에 남은 이전 장 편집을 자기 장 기준으로 마저 계산해 저장하기 위함 (§8-5).
        // 이전 장이 합성되지 못했다면(빠른 연속 전환) 그 전 문맥을 그대로 둔다.
        if let retiring = state.currentSession {
            state.retiredSession = retiring
        }
        // 이전 장의 미저장분은 pendingMutations 에 장 정보와 함께 남아 있으므로 여기서 버리지 않는다. 큐의 편집도 세대로 골라내므로 남긴다.
        state.chapter = chapter
        state.expectedVerseCount = expectedVerseCount
        state.layout = nil
        state.pendingLayout = nil
        state.pendingColumnOrigin = nil
        // 안전망 판정은 장마다 새로 낸다 — 이전 장의 Δ 로 새 장의 입력을 막지 않는다 (§14 이월 상태 감사).
        state.layoutDelta = nil
        state.pendingReload = false
        state.loadedDrawings = nil
        state.loadFailure = nil
        state.renderedData = nil
        // 세대를 올려 뷰가 빈 캔버스를 즉시 표시하게 한다 — 이전 장 잉크가 새 장 본문 위에 남지 않게.
        state.renderedRevision += 1
        state.renderedLayout = nil
        state.ownership = nil
        state.activeRowIDs = [:]
        state.layoutMismatchVerses = []
        state.legacyVerses = []
        state.undecodableVerses = []
        state.legacyInkBounds = nil
        state.lastDirtyBounds = nil
        state.lastEditedVerse = nil
        state.baselineData = nil
        state.isEditing = false
        state.isReloading = false
        state.reloadWhenSettled = false
        // 진행 중이던 지우기는 이전 장의 활성 행을 가리키므로 새 장으로 이어가지 않는다 (§14 이월 상태 감사).
        state.eraseTask = nil
        state.eraseAlert = nil
        state.scrollRequest = nil
        state.$canUndo.withLock { $0 = false }
        state.$canRedo.withLock { $0 = false }
        // 장 전환은 flush 지점이다 (§8-5). 실패해 남아 있던 이전 장 batch 를 여기서 다시 시도한다.
        return .merge(
            requestLoad(state: &state),
            startSaveIfPossible(state: &state, allowRetry: true)
        )
    }

    private func requestLoad(state: inout State) -> Effect<Action> {
        let requestID = uuid()
        state.loadRequestID = requestID
        let chapter = state.chapter
        return .run { [repository] send in
            do {
                let snapshots = try await repository.load(chapter: chapter)
                await send(.drawingsLoaded(requestID: requestID, .success(snapshots)))
            } catch {
                await send(.drawingsLoaded(requestID: requestID, .failure(DrawingLoadFailure(message: "\(error)"))))
            }
        }
    }

    private func finishLoad(
        state: inout State,
        requestID: UUID,
        result: Result<[VerseDrawingSnapshot], DrawingLoadFailure>
    ) -> Effect<Action> {
        // 이전 장(또는 이전 요청)의 결과는 폐기한다 (§6-4).
        guard requestID == state.loadRequestID else { return .none }
        switch result {
        case .success(let snapshots):
            state.loadedDrawings = snapshots
            state.loadFailure = nil
            if state.isReloading, !state.isFullyPersisted {
                // 재조회 결과가 아직 저장 중인 편집보다 앞선다. 저장이 정리되면 다시 읽는다 — 지금 합성하면 그 편집이 화면에서 빠진다.
                state.reloadWhenSettled = true
                return .none
            }
        case .failure(let failure):
            state.loadFailure = failure
            guard state.isReloading, state.loadedDrawings != nil else {
                // 첫 조회 실패를 빈 장으로 취급하면 기존 행 위에 새 행이 생긴다. 게이트를 닫아 둔다.
                return .none
            }
            // 재조회 실패 — 입력을 영원히 잠그는 대신 마지막으로 알고 있는 내용으로 다시 합성한다 (성공한 저장은 이미 겹쳐져 있다).
            Log.error("단일 Canvas 재조회 실패 — 마지막으로 알고 있는 내용으로 합성", failure.message)
            recoverFromReloadFailure(state: &state)
            return .none
        }
        composeIfReady(state: &state)
        return .none
    }

    /// 재합성 대기 중 저장·재조회가 실패했을 때의 출구 — `DB 내용 ⊕ 미저장분` 으로 지금 합성해 입력을 다시 연다.
    ///
    /// 코덱이 편집을 계산하는 중이면 미룬다. 지금 합성하면 그 결과가 세대를 잃는다. 큐가 비는 `finishEdit` 이
    /// 저장을 다시 시도하고, 그 실패가 여기로 돌아온다.
    func recoverFromReloadFailure(state: inout State) {
        guard state.editQueue.isEmpty, !state.isPreparingEdit else {
            state.reloadWhenSettled = true
            return
        }
        composeIfReady(state: &state)
    }

    private func applyLayout(state: inout State, layout: ChapterLayout) -> Effect<Action> {
        guard layout != state.layout else { return .none }
        state.layout = layout
        return state.isComposed ? reloadAfterSettling(state: &state) : composeAndReturn(state: &state)
    }

    private func applyColumnOrigin(state: inout State, origin: CGPoint) -> Effect<Action> {
        guard origin != state.columnOrigin else { return .none }
        state.columnOrigin = origin
        return state.isComposed ? reloadAfterSettling(state: &state) : composeAndReturn(state: &state)
    }

    /// 편집 중 보류해 둔 레이아웃 · `columnOrigin` · 복원 재합성을 pencil-up 뒤에 **한 번에** 적용한다.
    private func applyDeferredChanges(state: inout State) -> Effect<Action> {
        var changed = false
        if let layout = state.pendingLayout {
            state.pendingLayout = nil
            if layout != state.layout {
                state.layout = layout
                changed = true
            }
        }
        if let origin = state.pendingColumnOrigin {
            state.pendingColumnOrigin = nil
            if origin != state.columnOrigin {
                state.columnOrigin = origin
                changed = true
            }
        }
        let reload = state.pendingReload
        state.pendingReload = false
        guard changed || reload else { return .none }
        return state.isComposed ? reloadAfterSettling(state: &state) : composeAndReturn(state: &state)
    }

    private func composeAndReturn(state: inout State) -> Effect<Action> {
        composeIfReady(state: &state)
        return .none
    }

    /// §6-4 의 `composeIfReady`. 양쪽 입력이 모두 있고 §6-2 게이트를 통과할 때만 합성한다.
    ///
    /// 합성 입력은 `DB 내용 ⊕ 이 장의 미저장분` 이다. 저장이 실패한 채 장을 떠났다 돌아와도, 재합성 중 저장이 실패해도
    /// 미저장 잉크가 화면에서 사라지지 않는다. 미저장 행이 대표 행이 되므로 `activeRowIDs` 도 그 행을 가리킨다.
    private func composeIfReady(state: inout State) {
        guard let layout = state.layout,
              let loaded = state.loadedDrawings,
              let expected = state.expectedVerseCount,
              layout.satisfiesCompositionGate(expectedVerseCount: expected) else { return }

        let unsaved = state.pendingMutations.values
            .filter { $0.chapter == state.chapter }
            .sorted { $0.revision < $1.revision }
            .map(\.mutation)
        let snapshots = overlay(loaded, with: unsaved)
        let composed = codec.compose(snapshots, layout, state.columnOrigin)
        // 지금까지의 문맥을 물려 둔다 — 캔버스 교체 직전에 보고된(이전 세대) 편집을 옛 기준으로 계산하기 위함.
        if let retiring = state.currentSession {
            state.retiredSession = retiring
        }
        state.renderedData = composed.data
        state.renderedRevision += 1
        state.renderedLayout = layout
        state.renderedColumnOrigin = state.columnOrigin
        state.ownership = composed.ownership
        state.activeRowIDs = composed.activeRowIDs
        state.layoutMismatchVerses = composed.layoutMismatchVerses
        state.legacyVerses = composed.legacyVerses
        state.undecodableVerses = composed.undecodableVerses
        state.legacyInkBounds = composed.legacyInkBounds
        state.baselineData = composed.data
        state.isReloading = false
        if !composed.undecodableVerses.isEmpty {
            Log.error("단일 Canvas — 디코드할 수 없는 필사 행. 표시·활성 행에서 제외, 다음 편집은 새 행으로",
                      "\(state.chapter.title.rawValue).\(state.chapter.chapter)",
                      "verses=\(composed.undecodableVerses.sorted())")
        }
    }

    /// 저장 명령을 스냅샷 위에 겹친다 — 저장소의 `create`(upsert) · `replace` · `clear`(행 유지, 없으면 빈 행) 와 같은 의미다.
    func overlay(_ snapshots: [VerseDrawingSnapshot], with mutations: [VerseDrawingMutation]) -> [VerseDrawingSnapshot] {
        guard !mutations.isEmpty else { return snapshots }
        let now = date.now
        var result = snapshots
        var indexByRow: [BibleDrawingRowID: Int] = [:]
        for (index, snapshot) in result.enumerated() { indexByRow[snapshot.rowID] = index }

        func upsert(_ snapshot: VerseDrawingSnapshot) {
            if let index = indexByRow[snapshot.rowID] {
                result[index] = snapshot
            } else {
                indexByRow[snapshot.rowID] = result.count
                result.append(snapshot)
            }
        }

        for mutation in mutations {
            let existing = indexByRow[mutation.rowID].map { result[$0] }
            switch mutation {
            case .create(let verse, let rowID, let data, let metadata), .replace(let verse, let rowID, let data, let metadata):
                upsert(VerseDrawingSnapshot(
                    verse: verse, rowID: rowID, isPresent: existing?.isPresent ?? true, updateDate: now,
                    lineData: data, drawingVersion: 3, metadata: metadata
                ))
            case .clear(let verse, let rowID):
                upsert(VerseDrawingSnapshot(
                    verse: verse, rowID: rowID, isPresent: existing?.isPresent ?? true, updateDate: now,
                    lineData: nil, drawingVersion: existing?.drawingVersion ?? 3, metadata: existing?.metadata
                ))
            }
        }
        return result.sorted { lhs, rhs in lhs.verse != rhs.verse ? lhs.verse < rhs.verse : lhs.rowID < rhs.rowID }
    }

    /// 미저장분이 전부 저장된 뒤 DB 에서 다시 합성한다. 저장할 것이 없으면 즉시 다시 읽는다.
    ///
    /// - Note: `private` 이 아닌 이유는 지우기(`ChapterCanvasEraseFeature.swift`)가 같은 진입점을 쓰기 때문이다.
    ///         `startSaveIfPossible` · `settleIfNeeded` 도 같다.
    func reloadAfterSettling(state: inout State) -> Effect<Action> {
        state.reloadWhenSettled = true
        state.isReloading = true
        // 지우기가 도는 중이면 재조회를 시작하지 않는다 — 보관 트랜잭션과 겹치면 지우기 이전 내용으로 합성될 수 있다.
        // 예약(`reloadWhenSettled`)은 남으므로 `finishErase` 뒤에 수행된다.
        if state.isFullyPersisted, !state.isErasing {
            return startReload(state: &state)
        }
        return startSaveIfPossible(state: &state, allowRetry: true)
    }

    func startReload(state: inout State) -> Effect<Action> {
        state.reloadWhenSettled = false
        state.isReloading = true
        // `loadedDrawings` 는 비우지 않는다 — 재조회가 실패하면 그것이 마지막 근거다.
        return requestLoad(state: &state)
    }
}

// MARK: - 편집 (§8-1 · §8-2)

extension ChapterCanvasFeature {
    /// 큐의 첫 편집을 자기 세대의 문맥으로 코덱에 보낸다. 한 번에 하나만 — 다음 편집의 before 는 이 편집의 결과다.
    ///
    /// 재합성 대기 중(`isReloading`)에도 돈다. 재조회는 큐가 빌 때까지 시작하지 않으므로(`isFullyPersisted`)
    /// 기준(`baselineData`)은 아직 유효하고, 여기서 막으면 큐와 재조회가 서로를 기다린다.
    private func drainEditQueue(state: inout State) -> Effect<Action> {
        guard !state.isPreparingEdit else { return .none }
        while let next = state.editQueue.first {
            guard let session = state.session(for: next.snapshot.generation) else {
                Log.error("단일 Canvas — 계산 기준이 사라진 편집을 버린다",
                          "generation=\(next.snapshot.generation)", "revision=\(next.revision)")
                state.editQueue.removeFirst()
                continue
            }
            state.isPreparingEdit = true
            let context = DrawingEditContext(
                layout: session.layout, columnOrigin: session.columnOrigin, activeRowIDs: session.activeRowIDs
            )
            let before = session.baselineData
            let ownership = session.ownership
            let after = next.snapshot.drawingData
            let revision = next.revision
            return .run { [codec] send in
                let result = codec.mutations(before, ownership, after, context)
                await send(.mutationsPrepared(revision: revision, result))
            }
        }
        return .none
    }

    private func finishEdit(state: inout State, revision: Int, result: DrawingEditResult) -> Effect<Action> {
        state.isPreparingEdit = false
        guard let index = state.editQueue.firstIndex(where: { $0.revision == revision }) else {
            return drainEditQueue(state: &state)
        }
        let processed = state.editQueue.remove(at: index)
        let generation = processed.snapshot.generation

        // 결과를 자기 세대의 문맥에 반영한다 — §8-7 신규 행의 rowID 는 즉시 예약해 다음 편집이 같은 행으로 가게 한다.
        let chapter: BibleChapter
        if generation == state.renderedRevision {
            state.baselineData = processed.snapshot.drawingData
            state.ownership = result.ownership
            for (verse, rowID) in result.issuedRowIDs {
                state.activeRowIDs[verse] = rowID
            }
            chapter = state.chapter
        } else if var retired = state.retiredSession, retired.generation == generation {
            retired.baselineData = processed.snapshot.drawingData
            retired.ownership = result.ownership
            for (verse, rowID) in result.issuedRowIDs {
                retired.activeRowIDs[verse] = rowID
            }
            state.retiredSession = retired
            chapter = retired.chapter
            if chapter == state.chapter {
                // 같은 장의 이전 세대 편집 — 저장은 되지만 지금 화면(새 합성)에는 없다. 저장이 끝나면 다시 읽어 화면에 올린다.
                state.reloadWhenSettled = true
            }
        } else {
            // 코덱이 도는 사이 세대가 두 번 바뀌었다. 결과를 어느 장에도 귀속시킬 수 없다.
            Log.error("단일 Canvas — 결과의 세대가 사라져 편집을 버린다", "generation=\(generation)", "revision=\(revision)")
            return drainEditQueue(state: &state)
        }

        // §8-3 — rowID 키 last-wins. 더 최신 revision 이 이미 있으면 덮지 않는다.
        for mutation in result.mutations {
            let key = mutation.rowID
            var merged = mutation
            if let existing = state.pendingMutations[key] {
                if existing.revision > revision { continue }
                merged = Self.coalesce(existing: existing.mutation, incoming: mutation)
            }
            state.pendingMutations[key] = PendingDrawingMutation(revision: revision, chapter: chapter, mutation: merged)
        }

        return .merge(
            drainEditQueue(state: &state),
            startSaveIfPossible(state: &state, allowRetry: true)
        )
    }
}
