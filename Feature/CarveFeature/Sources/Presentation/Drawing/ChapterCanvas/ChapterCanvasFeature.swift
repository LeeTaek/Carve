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
struct CanvasEditSnapshot: Equatable, Sendable {
    /// 편집 직후 캔버스 content 좌표 drawing.
    let drawingData: Data
    /// 변경 영역. 디버그 표시용이며 저장 계산에는 쓰지 않는다.
    let dirtyBounds: CGRect?
    let reason: EditReason
}

enum EditReason: Equatable, Sendable { case ink, erase, undo, redo }

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
struct DrawingLoadFailure: Error, Equatable, Sendable {
    let message: String
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
/// editBegan → isEditing (layout 교체 보류)
/// editEnded(revision) → editQueue → 코덱 (한 번에 하나: 다음 편집의 before = 이전 편집의 결과)
///   → mutationsPrepared → ownership 승계 · 신규 rowID 예약 · pendingMutations 에 rowID 키로 coalescing
///   → 저장은 동시에 하나 (saveStatus) → saveFinished → revision 이 같은 항목만 제거 → 다음 batch
/// 실패 → 화면 유지 + 큐 보존 + 다음 편집/flush 에서 재시도 (§8-4)
/// ```
///
/// 레이아웃·`columnOrigin` 변경과 히스토리 복원은 **미저장분을 먼저 저장한 뒤 DB 에서 다시 합성**한다.
/// 캔버스에는 아직 저장되지 않은 잉크가 있을 수 있는데, DB 스냅샷으로 곧바로 다시 합성하면 그 잉크가 화면에서 사라지기 때문이다.
@Reducer
struct ChapterCanvasFeature {
    @ObservableState
    struct State: Equatable {
        var chapter: BibleChapter

        // §6-4 — 도착 순서가 보장되지 않는 두 입력과 게이트
        var expectedVerseCount: Int?
        var layout: ChapterLayout?
        var loadedDrawings: [VerseDrawingSnapshot]?
        var loadRequestID: UUID?
        var loadFailure: DrawingLoadFailure?
        /// 캔버스 content 좌표 = layout 좌표 + columnOrigin (§5). 값은 호스팅이 준다.
        var columnOrigin: CGPoint = .zero

        // 합성 결과
        var renderedData: Data?
        var renderedRevision = 0
        var ownership: OwnershipSnapshot?
        var activeRowIDs: [Int: BibleDrawingRowID] = [:]
        var layoutMismatchVerses: Set<Int> = []
        var legacyVerses: Set<Int> = []

        // §8-1 편집 계약
        var editRevision = 0
        var persistedRevision = 0
        var isEditing = false
        var pendingLayout: ChapterLayout?
        /// pencil-up 순서의 처리 대기 편집. 코덱은 한 번에 하나만 돈다.
        var editQueue: [QueuedEdit] = []
        var isPreparingEdit = false
        /// 코덱이 마지막으로 처리한 캔버스 내용 — 다음 편집의 before.
        var baselineData: Data?

        // §8-3 저장 대기열
        var pendingMutations: [BibleDrawingRowID: PendingDrawingMutation] = [:]
        var saveStatus: SaveStatus = .idle
        /// 지금 저장 중인 batch 의 rowID → revision. 성공 시 같은 revision 인 항목만 제거한다 (§8-3 5번).
        var inFlightBatch: [BibleDrawingRowID: Int] = [:]
        /// 미저장분이 전부 저장되면 DB 에서 다시 합성한다 (레이아웃 변경 · 복원).
        var reloadWhenSettled = false
        var isReloading = false

        var canUndo = false
        var canRedo = false

        struct QueuedEdit: Equatable, Sendable {
            let revision: Int
            let snapshot: CanvasEditSnapshot
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
    }

    enum Action: Equatable {
        /// 장 진입. 이전 장의 미저장분은 버리지 않고 자기 장으로 저장된다.
        case load(chapter: BibleChapter, expectedVerseCount: Int)
        case drawingsLoaded(requestID: UUID, Result<[VerseDrawingSnapshot], DrawingLoadFailure>)
        case layoutCompleted(ChapterLayout)
        case columnOriginChanged(CGPoint)

        case editBegan
        case editEnded(CanvasEditSnapshot)
        case mutationsPrepared(revision: Int, DrawingEditResult)
        case saveFinished(revision: Int, failure: DrawingRepositoryError?)
        /// 장 전환 · 백그라운드 진입 시 대기열 저장 (§8-5). 실패했던 저장의 재시도이기도 하다.
        case flushPending
        /// 히스토리에서 다른 회차를 선택해 `isPresent` 가 바뀐 뒤. mutation 을 만들지 않고 다시 합성한다 (§8-7).
        case verseRowRestored(verse: Int, rowID: BibleDrawingRowID)
        case undoStateChanged(canUndo: Bool, canRedo: Bool)
    }

    @Dependency(\.drawingCodec) var codec
    @Dependency(\.drawingRepository) var repository
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load(let chapter, let expectedVerseCount):
                return beginLoad(state: &state, chapter: chapter, expectedVerseCount: expectedVerseCount)

            case .drawingsLoaded(let requestID, let result):
                // 이전 장(또는 이전 요청)의 결과는 폐기한다 (§6-4).
                guard requestID == state.loadRequestID else { return .none }
                switch result {
                case .success(let snapshots):
                    state.loadedDrawings = snapshots
                    state.loadFailure = nil
                case .failure(let failure):
                    // 조회 실패를 빈 장으로 취급하면 기존 행 위에 새 행이 생긴다. 게이트를 닫아 둔다.
                    state.loadedDrawings = nil
                    state.loadFailure = failure
                }
                composeIfReady(state: &state)
                return .none

            case .layoutCompleted(let layout):
                if state.isEditing {
                    state.pendingLayout = layout
                    return .none
                }
                return applyLayout(state: &state, layout: layout)

            case .columnOriginChanged(let origin):
                guard origin != state.columnOrigin else { return .none }
                state.columnOrigin = origin
                return state.isComposed ? reloadAfterSettling(state: &state) : composeAndReturn(state: &state)

            case .editBegan:
                state.isEditing = true
                return .none

            case .editEnded(let snapshot):
                state.isEditing = false
                state.editRevision += 1
                state.editQueue.append(State.QueuedEdit(revision: state.editRevision, snapshot: snapshot))
                var effects: [Effect<Action>] = [drainEditQueue(state: &state)]
                if let pending = state.pendingLayout {
                    state.pendingLayout = nil
                    effects.append(applyLayout(state: &state, layout: pending))
                }
                return .merge(effects)

            case .mutationsPrepared(let revision, let result):
                return finishEdit(state: &state, revision: revision, result: result)

            case .saveFinished(let revision, let failure):
                return finishSave(state: &state, revision: revision, failure: failure)

            case .flushPending:
                return startSaveIfPossible(state: &state, allowRetry: true)

            case .verseRowRestored:
                // isPresent 이전은 호출부(히스토리 시트)가 이미 DB 에 반영했다. 여기서는 mutation 없이 다시 합성만 한다.
                return reloadAfterSettling(state: &state)

            case .undoStateChanged(let canUndo, let canRedo):
                state.canUndo = canUndo
                state.canRedo = canRedo
                return .none
            }
        }
    }
}

// MARK: - 조회 · 합성 (§6-4)

extension ChapterCanvasFeature {
    private func beginLoad(state: inout State, chapter: BibleChapter, expectedVerseCount: Int) -> Effect<Action> {
        // 이전 장의 미저장분은 pendingMutations 에 장 정보와 함께 남아 있으므로 여기서 버리지 않는다.
        state.chapter = chapter
        state.expectedVerseCount = expectedVerseCount
        state.layout = nil
        state.pendingLayout = nil
        state.loadedDrawings = nil
        state.loadFailure = nil
        state.renderedData = nil
        state.ownership = nil
        state.activeRowIDs = [:]
        state.layoutMismatchVerses = []
        state.legacyVerses = []
        state.baselineData = nil
        state.editQueue = []
        state.isEditing = false
        state.isReloading = false
        state.reloadWhenSettled = false
        state.canUndo = false
        state.canRedo = false
        return requestLoad(state: &state)
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

    private func applyLayout(state: inout State, layout: ChapterLayout) -> Effect<Action> {
        guard layout != state.layout else { return .none }
        state.layout = layout
        return state.isComposed ? reloadAfterSettling(state: &state) : composeAndReturn(state: &state)
    }

    private func composeAndReturn(state: inout State) -> Effect<Action> {
        composeIfReady(state: &state)
        return .none
    }

    /// §6-4 의 `composeIfReady`. 양쪽 입력이 모두 있고 §6-2 게이트를 통과할 때만 합성한다.
    private func composeIfReady(state: inout State) {
        guard let layout = state.layout,
              let loaded = state.loadedDrawings,
              let expected = state.expectedVerseCount,
              layout.satisfiesCompositionGate(expectedVerseCount: expected) else { return }

        let composed = codec.compose(loaded, layout, state.columnOrigin)
        state.renderedData = composed.data
        state.renderedRevision += 1
        state.ownership = composed.ownership
        state.activeRowIDs = composed.activeRowIDs
        state.layoutMismatchVerses = composed.layoutMismatchVerses
        state.legacyVerses = composed.legacyVerses
        state.baselineData = composed.data
        state.isReloading = false
        state.reloadWhenSettled = false
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
        state.loadedDrawings = nil
        return requestLoad(state: &state)
    }
}

// MARK: - 편집 (§8-1 · §8-2)

extension ChapterCanvasFeature {
    /// 큐의 첫 편집을 코덱에 보낸다. 한 번에 하나만 — 다음 편집의 before 는 이 편집의 결과다.
    private func drainEditQueue(state: inout State) -> Effect<Action> {
        guard !state.isPreparingEdit,
              !state.isReloading,
              let next = state.editQueue.first,
              let layout = state.layout,
              let ownership = state.ownership,
              let before = state.baselineData else { return .none }

        state.isPreparingEdit = true
        let context = DrawingEditContext(layout: layout, columnOrigin: state.columnOrigin, activeRowIDs: state.activeRowIDs)
        let after = next.snapshot.drawingData
        let revision = next.revision
        return .run { [codec] send in
            let result = codec.mutations(before, ownership, after, context)
            await send(.mutationsPrepared(revision: revision, result))
        }
    }

    private func finishEdit(state: inout State, revision: Int, result: DrawingEditResult) -> Effect<Action> {
        state.isPreparingEdit = false
        guard let index = state.editQueue.firstIndex(where: { $0.revision == revision }) else {
            // 장 전환으로 큐가 비워진 뒤 도착한 결과 — 이 장의 것이 아니다.
            return .none
        }
        let processed = state.editQueue.remove(at: index)
        state.baselineData = processed.snapshot.drawingData
        state.ownership = result.ownership

        // §8-7 — 신규 행의 rowID 를 즉시 예약한다. 다음 편집은 같은 행으로 간다.
        for (verse, rowID) in result.issuedRowIDs {
            state.activeRowIDs[verse] = rowID
        }
        // §8-3 — rowID 키 last-wins. 더 최신 revision 이 이미 있으면 덮지 않는다.
        for mutation in result.mutations {
            let key = mutation.rowID
            var merged = mutation
            if let existing = state.pendingMutations[key] {
                if existing.revision > revision { continue }
                merged = Self.coalesce(existing: existing.mutation, incoming: mutation)
            }
            state.pendingMutations[key] = PendingDrawingMutation(revision: revision, chapter: state.chapter, mutation: merged)
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
    /// 아직 저장되지 않은(또는 저장이 실패한) `create` 위에 `replace` 가 오면 **`create` 로 남긴다** — 행이 아직 없을 수 있어서다.
    /// 저장소의 `create` 는 upsert 라 이미 만들어졌어도 갱신으로 동작한다. `create` 위의 `clear` 는 `clear` 로 두며,
    /// 저장소가 행이 없으면 빈 행을 만들어 준다. 그 밖에는 나중 명령이 이긴다 (`replace` 는 절의 완전한 획 집합이므로).
    static func coalesce(existing: VerseDrawingMutation, incoming: VerseDrawingMutation) -> VerseDrawingMutation {
        switch (existing, incoming) {
        case (.create(let verse, let rowID, _, _), .replace(_, _, let data, let metadata)):
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
        state.inFlightBatch = batch.mapValues(\.revision)
        state.saveStatus = .saving(revision: revision)

        let mutations = batch.values
            .sorted { $0.mutation.verse != $1.mutation.verse ? $0.mutation.verse < $1.mutation.verse : $0.mutation.rowID < $1.mutation.rowID }
            .map(\.mutation)
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
        state.inFlightBatch = [:]

        if let failure {
            let retryCount: Int
            if case .failed(_, let previous) = state.saveStatus { retryCount = previous + 1 } else { retryCount = 1 }
            state.saveStatus = .failed(revision: revision, retryCount: retryCount)
            Log.error("단일 Canvas 저장 실패 — 큐 보존, 다음 편집/flush 에서 재시도", "\(failure)", "revision=\(revision)")
            return .none
        }

        // §8-3 5번 — 저장 중 도착한 더 최신 revision 은 남겨 두고 다음 batch 에서 저장한다.
        for (rowID, savedRevision) in batch where state.pendingMutations[rowID]?.revision == savedRevision {
            state.pendingMutations[rowID] = nil
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
