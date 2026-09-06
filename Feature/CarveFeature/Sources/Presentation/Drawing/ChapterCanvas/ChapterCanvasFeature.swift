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
        /// §6-2 입력 게이트 — 합성이 끝났고 다시 합성하는 중이 아닐 때만 입력을 받는다.
        var isInputEnabled: Bool { isComposed && !isReloading }
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

            case .editBegan:
                state.isEditing = true
                return .none

            case .editCancelled:
                state.isEditing = false
                return applyDeferredChanges(state: &state)

            case .editEnded(let snapshot):
                state.isEditing = false
                var effects: [Effect<Action>] = []
                if state.session(for: snapshot.generation) != nil {
                    state.editRevision += 1
                    state.editQueue.append(State.QueuedEdit(revision: state.editRevision, snapshot: snapshot))
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
            }
        }
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
        state.baselineData = nil
        state.isEditing = false
        state.isReloading = false
        state.reloadWhenSettled = false
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
    private func recoverFromReloadFailure(state: inout State) {
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
        state.baselineData = composed.data
        state.isReloading = false
        if !composed.undecodableVerses.isEmpty {
            Log.error("단일 Canvas — 디코드할 수 없는 필사 행. 표시·활성 행에서 제외, 다음 편집은 새 행으로",
                      "\(state.chapter.title.rawValue).\(state.chapter.chapter)",
                      "verses=\(composed.undecodableVerses.sorted())")
        }
    }

    /// 저장 명령을 스냅샷 위에 겹친다 — 저장소의 `create`(upsert) · `replace` · `clear`(행 유지, 없으면 빈 행) 와 같은 의미다.
    private func overlay(_ snapshots: [VerseDrawingSnapshot], with mutations: [VerseDrawingMutation]) -> [VerseDrawingSnapshot] {
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
    private func reloadAfterSettling(state: inout State) -> Effect<Action> {
        state.reloadWhenSettled = true
        state.isReloading = true
        if state.isFullyPersisted {
            return startReload(state: &state)
        }
        return startSaveIfPossible(state: &state, allowRetry: true)
    }

    private func startReload(state: inout State) -> Effect<Action> {
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

// MARK: - 저장 (§8-3 · §8-4)

extension ChapterCanvasFeature {
    /// 같은 rowID 의 pending 항목 위에 새 명령을 겹칠 때의 규칙.
    ///
    /// 저장소의 `create` 는 upsert 이고 `clear` 는 행이 없으면 빈 행을 만들지만, **`replace` 는 행이 없으면 실패한다** (§8-6).
    /// 그래서 행이 아직 DB 에 없을 수 있는 자리에는 `replace` 를 남기지 않는다.
    ///
    /// | 기존 | 새 명령 | 결과 | 이유 |
    /// |---|---|---|---|
    /// | `create` | `replace` | `create` | 행이 아직 없을 수 있다 |
    /// | `clear` | `replace` | `create` | 그 `clear` 가 미저장 `create` 를 덮은 것일 수 있다 — `replace` 로 남기면 `rowNotFound` 로 batch 전체가 영구 실패한다 |
    /// | 그 밖 | — | 새 명령 | `replace` 는 절의 완전한 획 집합이므로 나중 명령이 이긴다 |
    static func coalesce(existing: VerseDrawingMutation, incoming: VerseDrawingMutation) -> VerseDrawingMutation {
        switch (existing, incoming) {
        case (.create(let verse, let rowID, _, _), .replace(_, _, let data, let metadata)),
             (.clear(let verse, let rowID), .replace(_, _, let data, let metadata)):
            return .create(verse: verse, rowID: rowID, data: data, metadata: metadata)
        default:
            return incoming
        }
    }

    /// 저장은 동시에 하나만. `allowRetry` 면 실패 상태에서도 다시 시도한다.
    private func startSaveIfPossible(state: inout State, allowRetry: Bool) -> Effect<Action> {
        switch state.saveStatus {
        case .saving:
            return .none
        case .failed where !allowRetry:
            return .none
        case .idle, .failed:
            break
        }
        guard !state.pendingMutations.isEmpty else {
            return settleIfNeeded(state: &state)
        }

        // 한 batch 는 한 장이다. 이전 장의 미저장분이 남아 있으면 그것부터 보낸다.
        let chapter = state.pendingMutations.values
            .map(\.chapter)
            .min { lhs, rhs in lhs != state.chapter && rhs == state.chapter } ?? state.chapter
        let batch = state.pendingMutations.filter { $0.value.chapter == chapter }
        let revision = batch.values.map(\.revision).max() ?? state.editRevision
        let mutations = batch.values
            .sorted { $0.mutation.verse != $1.mutation.verse ? $0.mutation.verse < $1.mutation.verse : $0.mutation.rowID < $1.mutation.rowID }
            .map(\.mutation)
        state.inFlightBatch = batch.mapValues(\.revision)
        state.inFlightMutations = mutations
        state.inFlightChapter = chapter
        state.saveStatus = .saving(revision: revision)

        return .run { [repository] send in
            do {
                try await repository.apply(mutations, chapter: chapter)
                await send(.saveFinished(revision: revision, failure: nil))
            } catch let error as DrawingRepositoryError {
                await send(.saveFinished(revision: revision, failure: error))
            } catch {
                await send(.saveFinished(revision: revision, failure: .persistenceFailed("\(error)")))
            }
        }
    }

    private func finishSave(state: inout State, revision: Int, failure: DrawingRepositoryError?) -> Effect<Action> {
        let batch = state.inFlightBatch
        let mutations = state.inFlightMutations
        let chapter = state.inFlightChapter
        state.inFlightBatch = [:]
        state.inFlightMutations = []
        state.inFlightChapter = nil

        if let failure {
            let retryCount: Int
            if case .failed(_, let previous) = state.saveStatus { retryCount = previous + 1 } else { retryCount = 1 }
            state.saveStatus = .failed(revision: revision, retryCount: retryCount)
            Log.error("단일 Canvas 저장 실패 — 큐 보존, 다음 편집/flush 에서 재시도", "\(failure)", "revision=\(revision)")
            if state.reloadWhenSettled {
                // 재합성이 저장 완료를 기다리는 중이다. 입력을 잠근 채 두면 재시도할 편집 자체가 생기지 않는다 —
                // DB 내용 ⊕ 미저장분으로 지금 합성해 입력을 열고, DB 재조회는 다음 저장 성공 뒤로 미룬다 (reloadWhenSettled 유지).
                Log.error("단일 Canvas — 저장 실패 상태에서 미저장분을 겹쳐 합성, 재조회는 저장 성공 뒤로")
                recoverFromReloadFailure(state: &state)
            }
            return .none
        }

        // §8-3 5번 — 저장 중 도착한 더 최신 revision 은 남겨 두고 다음 batch 에서 저장한다.
        for (rowID, savedRevision) in batch where state.pendingMutations[rowID]?.revision == savedRevision {
            state.pendingMutations[rowID] = nil
        }
        // 저장된 내용을 DB 내용에 겹쳐 둔다 — 재조회가 실패해도 `loadedDrawings ⊕ pendingMutations` 가 현재 내용이 되게.
        if chapter == state.chapter, let loaded = state.loadedDrawings {
            state.loadedDrawings = overlay(loaded, with: mutations)
        }
        state.persistedRevision = max(state.persistedRevision, revision)
        state.saveStatus = .idle
        return startSaveIfPossible(state: &state, allowRetry: false)
    }

    /// 저장할 것이 없을 때 — 다시 합성하기로 예약돼 있었다면 지금 읽는다.
    private func settleIfNeeded(state: inout State) -> Effect<Action> {
        guard state.reloadWhenSettled, state.isFullyPersisted else { return .none }
        return startReload(state: &state)
    }
}
