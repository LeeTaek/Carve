//
//  ChapterCanvasSaveFeature.swift
//  FeatureCarve
//
//  Copyright © 2026 leetaek. All rights reserved.
//
//  `ChapterCanvasFeature` 의 저장 경로 (설계 §8-3 · §8-4). 리듀서 본체에서 잘라 냈을 뿐 동작은 그대로다.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

// MARK: - 저장 상태 표시 (로드맵 SAVE-1)

/// 필사가 **이 기기에** 저장됐는지. iCloud 로 전해졌는지와는 무관하다.
///
/// | 상태 | 표시 |
/// |---|---|
/// | `pending` | 저장 대기 중 |
/// | `saving` | 저장 중… |
/// | `saved` | 이 기기에 저장됨 |
/// | `failed` | 지속 안내 + 「다시 시도」 (`SaveFailureNoticeView`) |
enum LocalSaveIndicator: Equatable, Sendable {
    /// 아직 쓴 것이 없다. 표시하지 않는다 — 저장할 것이 없었는데 "저장됨" 이라고 말하지 않는다.
    case none
    /// 아직 저장하지 않은 변경이 있다.
    case pending
    /// 저장 처리 중이다.
    case saving
    /// 지금까지의 변경이 이 기기에 저장됐다.
    case saved
    /// 저장에 실패했다. 성공 없이 이어진 실패 횟수를 함께 든다.
    case failed(retryCount: Int)
}

extension ChapterCanvasFeature.State {
    /// 지금 보여 줄 로컬 저장 상태.
    ///
    /// **실패가 가장 먼저다.** 실패한 채로 새 획을 그어도 미저장분이 남아 있으므로 실패 안내를 내리지 않는다 —
    /// 새 편집이 저장을 다시 시작하면 그때 `saving` 으로 바뀐다.
    var localSaveIndicator: LocalSaveIndicator {
        if case .failed(_, let count) = saveStatus { return .failed(retryCount: count) }
        // 초안이 유일한 보존인데 남기지 못했다 — 저장 실패와 같이 알린다(§12-6 구현 순서 ②).
        if let count = draftFailureCount { return .failed(retryCount: count) }
        if case .saving = saveStatus { return .saving }
        if isSavingDrafts { return .saving }
        if hasUnsavedChanges { return .pending }
        // 마지막으로 전부 지운 뒤에 쓴 것이 있을 때만. 이전 구현은 `editRevision > 0` 만 봐서
        // 필사를 전부 지운 직후에도 "이 기기에 저장됨" 이 떴다.
        return editRevision > editRevisionAtClear ? .saved : .none
    }

    /// 아직 저장하지 않은 변경이 있는가. **장과 무관하다** — 장을 바꿔도 남은 이전 장의 미저장분을 포함한다.
    ///
    /// 획을 긋는 중(`isEditing`)도 포함한다. 그 획은 아직 보고되지도 않았으므로 저장됐다고 말할 수 없다. 닫은 세션의 늦은 편집도
    /// 초안이 될 때까지 포함한다.
    var hasUnsavedChanges: Bool {
        isEditing || isPreparingEdit || !editQueue.isEmpty || hasUnsavedPending || !closedDrafts.pending.isEmpty
    }

    /// 아직 이 기기에 남지 않은 미저장분이 있는가. 저장소에 쓸 미저장분은 저장소 저장까지, 그 밖은 초안까지 본다 — 확인 대기 중에는
    /// 초안이 된 미저장분을 저장소 저장을 위해 큐에 붙잡아 두지만, 그 내용은 이미 이 기기에 남아 있다.
    var hasUnsavedPending: Bool {
        pendingMutations.contains { rowID, entry in isStoreBound(entry) || !isDrafted(rowID, entry) }
    }

    /// 다시 합성해도 되는가 — 획을 긋는 중이 아니고, 저장소 저장 · 초안 · 코덱이 멎었고, 남은 미저장분은 초안이 돼 다시 읽어도 겹쳐진다.
    ///
    /// `isFullyPersisted` 보다 넓다: 확인 대기 중 큐에 붙잡아 둔 미저장분은 이미 초안이라 다시 읽으면 지금 세션의 초안으로 다시 겹친다.
    /// 그것까지 기다리면 계정 확인이 오래 걸리는 동안(오프라인) 회전 · 복원 재합성이 입력을 잠근 채 멈춘다. 닫은 세션의 늦은 편집은
    /// 지금 세션의 합성과 무관하므로 기다리지 않는다.
    ///
    /// **획을 긋는 중(`isEditing`)도 기다린다**(2026-09-21 후속 리뷰 P0-3 필수 조건). 도구를 쓰는 동안과, 획이 끝난 뒤 뷰가 아직 보고하지 않은
    /// 동안(디바운스)이 모두 `editBegan` ~ `editEnded`/`editCancelled` 사이다. 그 사이 다시 합성하면 긋던 획이 화면에서 사라진다 — 늦게 도착한
    /// 필사의 다시 읽기가 그 순간에 올 수 있다. 뷰에만 있는 변경은 인계(`handoffToken`)로 받는다.
    var isSettledForReload: Bool {
        !isEditing && saveStatus == .idle && editQueue.isEmpty && !isPreparingEdit && !isSavingDrafts && !hasUnsavedPending
    }

    /// 저장에 실패해 **사용자에게 알려야 하는** 상태면 지금까지의 재시도 횟수. 아니면 nil.
    ///
    /// 실패해도 큐는 보존되고 다음 편집·flush 에서 자동으로 다시 시도한다(§8-4). 그래도 알리는 이유는
    /// 그 재시도가 언제 일어날지 사용자가 알 수 없고, **그 사이에 앱을 닫으면 미저장분이 사라지기** 때문이다.
    var saveRetryCount: Int? {
        if case .failed(_, let count) = saveStatus { return count }
        return draftFailureCount
    }
}

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
    /// 초안에만 있던 행(`DraftSessionState.draftOnlyRowIDs`)을 가리키는 `replace` 를 `create` 로 바꾼다 — 그 행은 저장소에 없으므로 `replace` 는
    /// `rowNotFound` 로 batch 전체를 실패시킨다. `create` 는 upsert 라 행이 이미 있어도 안전하다.
    static func targetingStore(_ mutation: VerseDrawingMutation, draftOnlyRowIDs: Set<BibleDrawingRowID>) -> VerseDrawingMutation {
        guard case .replace(let verse, let rowID, let data, let metadata) = mutation, draftOnlyRowIDs.contains(rowID) else { return mutation }
        return .create(verse: verse, rowID: rowID, data: data, metadata: metadata)
    }

    static func coalesce(existing: VerseDrawingMutation, incoming: VerseDrawingMutation) -> VerseDrawingMutation {
        switch (existing, incoming) {
        case (.create(let verse, let rowID, _, _), .replace(_, _, let data, let metadata)),
             (.clear(let verse, let rowID), .replace(_, _, let data, let metadata)):
            return .create(verse: verse, rowID: rowID, data: data, metadata: metadata)
        default:
            return incoming
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

    /// 저장은 동시에 하나만. `allowRetry` 면 실패 상태에서도 다시 시도한다.
    ///
    /// 초안은 저장소 저장과 따로 남긴다 — 닫는 중에도, 저장소에 쓰지 않는 세션에서도 편집은 초안이 된다(§12-6 구현 순서 ②).
    func startSaveIfPossible(state: inout State, allowRetry: Bool) -> Effect<Action> {
        let drafts = startDraftSaveIfPossible(state: &state, allowRetry: allowRetry)
        // 무효가 된 세션을 닫는 중이다 — 바뀐 계정 · 기준점 아래로 이전 세션의 편집을 저장하지 않는다(§12-6 구현 순서 ①).
        guard state.sessionEnd == nil else { return drafts }
        // 저장소로 가지 않는 미저장분(보존만 · 로그인하지 않은 세션, 보이기만 하는 초안을 이은 절) 가운데 초안이 된 것은 내린다.
        dropDraftedPending(state: &state)
        // 귀속할 근거가 없는 세션(보존만 · 확인 대기 · 로그인하지 않음)은 저장소에 쓰지 않는다 — `BibleDrawing` 은 동기화된다.
        guard state.persistsToStore else {
            return .merge(drafts, settleIfNeeded(state: &state))
        }
        switch state.saveStatus {
        case .saving:
            return drafts
        case .failed where !allowRetry:
            return drafts
        case .idle, .failed:
            break
        }
        // 저장소로는 그 revision 까지 초안이 내구성 있게 남은 것만 보낸다 — 저장소 저장이 먼저 끝나면, 초안을 쓰기 전에 앱이 끝나고 계정이 바뀌는
        // 순간 그 필기의 사본이 어디에도 없다(ACC-1 F29). 초안 저장 실패를 저장소 저장으로 대신하지 않는다. 초안 저장소가 없으면(시험 · 미리보기)
        // 기다릴 초안이 없다.
        let draftsFirst = draftStore != nil
        let storeBound = state.pendingMutations.filter { rowID, entry in
            state.isStoreBound(entry) && (!draftsFirst || state.isDrafted(rowID, entry))
        }
        guard !storeBound.isEmpty else {
            return .merge(drafts, settleIfNeeded(state: &state))
        }
        guard let generation = state.storeGeneration else {
            // 오지 않는 자리다 — 합성은 세대가 있을 때만 하고(`composeIfReady`) 미저장분은 합성한 내용 위에서만 생긴다.
            // 기준 없이 보내면 저장소가 대조할 수 없어 보내지 않는다.
            Log.error("단일 Canvas — 기준 세대 없이 미저장분이 있다. 저장하지 않고 남긴다", "count=\(storeBound.count)")
            return drafts
        }

        // 한 batch 는 한 장이다. 이전 장의 미저장분이 남아 있으면 그것부터 보낸다.
        let chapter = storeBound.values
            .map(\.chapter)
            .min { lhs, rhs in lhs != state.chapter && rhs == state.chapter } ?? state.chapter
        let batch = storeBound.filter { $0.value.chapter == chapter }
        let revision = batch.values.map(\.revision).max() ?? state.editRevision
        let mutations = batch.values
            .sorted { $0.mutation.verse != $1.mutation.verse ? $0.mutation.verse < $1.mutation.verse : $0.mutation.rowID < $1.mutation.rowID }
            .map(\.mutation)
        state.inFlightBatch = batch.mapValues(\.revision)
        state.inFlightMutations = mutations
        state.inFlightChapter = chapter
        let requestID = uuid()
        state.saveStatus = .saving(revision: revision, requestID: requestID)

        return .merge(drafts, .run { [repository] send in
            do {
                try await repository.apply(mutations, chapter: chapter, generation: generation)
                await send(.saveFinished(requestID: requestID, revision: revision, failure: nil))
            } catch let error as DrawingRepositoryError {
                await send(.saveFinished(requestID: requestID, revision: revision, failure: error))
            } catch {
                await send(.saveFinished(requestID: requestID, revision: revision, failure: .persistenceFailed("\(error)")))
            }
        })
    }

    func finishSave(state: inout State, requestID: UUID, revision: Int, failure: DrawingRepositoryError?) -> Effect<Action> {
        // ★ 지금 도는 저장의 응답인가. 이전 구현은 이것을 보지 않고 **현재의** 진행 중 기록을 가져가 처리해서,
        //   전체 삭제로 상태를 비운 뒤 시작한 새 저장이 있을 때 삭제 전 저장의 늦은 응답이 그 새 필사를 큐에서 지웠다.
        //   진행 중 기록은 이 저장의 것이 아니므로 건드리지 않는다.
        guard case .saving(_, let current) = state.saveStatus, current == requestID else {
            Log.error("단일 Canvas — 지금 도는 저장이 아닌 완료 응답을 버린다", "revision=\(revision)", "failure=\(String(describing: failure))")
            return .none
        }
        if failure == .staleStoreGeneration {
            // 저장소가 아무것도 쓰지 않고 거절했다 — 이 화면이 기준으로 삼은 조회 뒤에 필사 데이터가 전부 지워졌다.
            // 실패로 알리고 다시 시도하면 매번 같은 이유로 거절된다. 설정의 삭제 알림(`drawingDataCleared`)이 오기 전이라도
            // 같은 정리를 한다. 알림이 뒤따라 와도 결과가 같다 — 설정이 떠 있는 동안에는 새 편집이 생기지 않는다.
            Log.error("단일 Canvas — 저장이 세대에 걸려 거절됐다. 미저장분을 버리고 다시 읽는다", "revision=\(revision)")
            return clearAfterExternalDelete(state: &state)
        }
        let batch = state.inFlightBatch
        let mutations = state.inFlightMutations
        let chapter = state.inFlightChapter
        state.inFlightBatch = [:]
        state.inFlightMutations = []
        state.inFlightChapter = nil

        if let failure, state.pendingMutations.isEmpty, state.sessionEnd == nil {
            // 실패한 저장의 내용은 이미 격리했다 — 편집 세션을 닫으며 미저장분을 격리본으로 옮겼다(§12-6 구현 순서 ①).
            // 다시 시도할 것이 없으므로 실패로 남기지 않는다. 남기면 예약된 재합성이 저장 성공을 기다리며 멈춰 입력이 잠긴다.
            Log.info("단일 Canvas — 실패한 저장의 내용은 이미 격리했다. 다시 시도하지 않는다", "\(failure)", "revision=\(revision)")
            state.consecutiveSaveFailures = 0
            state.saveStatus = .idle
            return settleIfNeeded(state: &state)
        }
        if let failure {
            // 이전 구현은 직전 상태가 `.failed` 일 때만 +1 했다. 재시도는 항상 `.saving` 을 거치므로 값이 **늘 1** 이었다 —
            // 로그용일 때는 무해했지만 화면이 반복 실패를 구분하려면 실제로 누적돼야 한다.
            state.consecutiveSaveFailures += 1
            state.saveStatus = .failed(revision: revision, retryCount: state.consecutiveSaveFailures)
            Log.error("단일 Canvas 저장 실패 — 큐 보존, 다음 편집/flush 에서 재시도", "\(failure)", "revision=\(revision)")
            if state.reloadWhenSettled {
                // 재합성이 저장 완료를 기다리는 중이다. 입력을 잠근 채 두면 재시도할 편집 자체가 생기지 않는다 —
                // DB 내용 ⊕ 미저장분으로 지금 합성해 입력을 열고, DB 재조회는 다음 저장 성공 뒤로 미룬다 (reloadWhenSettled 유지).
                Log.error("단일 Canvas — 저장 실패 상태에서 미저장분을 겹쳐 합성, 재조회는 저장 성공 뒤로")
                recoverFromReloadFailure(state: &state)
            }
            if state.eraseTask?.phase == .flushing {
                // 지우기의 flush 가 실패했다. 저장하지 못한 획을 두고 보관하면 "방금까지 쓴 내용" 이 아닌 것을 보관한다.
                // 보관을 시작하지 않고 잠금만 풀어 준다 — 필기는 화면에 그대로 있고 큐도 보존된다 (§8-4).
                return failErase(state: &state)
            }
            return .none
        }

        // §8-3 5번 — 저장 중 도착한 더 최신 revision 은 남겨 두고 다음 batch 에서 저장한다.
        for (rowID, savedRevision) in batch where state.pendingMutations[rowID]?.revision == savedRevision {
            state.pendingMutations[rowID] = nil
        }
        // 저장소에 들어간 행 — 그 revision 까지의 초안은 역할이 끝났고(다시 읽을 때 겹치지 않는다), 이제 초안에만 있는 행이 아니다.
        // **초안은 지우지 않는다** — 전송 전에 계정이 바뀌면 미러링이 이 행을 지우고 되살리지 않는다(ACC-1 F29). 정리는 ③ 의 확정이 한다.
        for (rowID, savedRevision) in batch {
            state.drafts.storedRevisions[rowID] = max(state.drafts.storedRevisions[rowID] ?? 0, savedRevision)
            state.drafts.draftOnlyRowIDs.remove(rowID)
        }
        // 저장된 내용을 DB 내용에 겹쳐 둔다 — 재조회가 실패해도 `loadedDrawings ⊕ pendingMutations` 가 현재 내용이 되게.
        if chapter == state.chapter, let loaded = state.loadedDrawings {
            state.loadedDrawings = overlay(loaded, with: mutations)
        }
        state.persistedRevision = max(state.persistedRevision, revision)
        state.consecutiveSaveFailures = 0
        state.saveStatus = .idle
        // 방금 넣은 내용의 지문을 함께 남긴다 — 그 행이 나중에 이 내용으로 돌아오면 그 뒤 편집이 전송되지 않은 것이다.
        let sent = Dictionary(mutations.compactMap { mutation in
            Self.sentFingerprint(of: mutation).map { (mutation.rowID, $0) }
        }, uniquingKeysWith: { _, last in last })
        return .merge(
            markStoredDrafts(state: state, rows: Array(batch.keys), sent: sent),
            startSaveIfPossible(state: &state, allowRetry: false)
        )
    }

    /// 획이 끝났다(보고 · 취소) — 긋는 중이라 미뤄 둔 다시 읽기가 있으면 이제 한다(`isSettledForReload` 는 긋는 중을 기다린다).
    func settleAfterEdit(state: inout State) -> Effect<Action> {
        state.reloadWhenSettled ? settleIfNeeded(state: &state) : .none
    }

    /// 저장할 것이 없을 때 — 지우기가 기다리고 있으면 지금 보관하고, 아니면 예약된 재합성을 지금 읽는다.
    func settleIfNeeded(state: inout State) -> Effect<Action> {
        // 지우기가 재합성보다 앞선다. flush 가 끝난 **지금**의 DB 가 "방금까지 쓴 내용" 이고, 그것이 보관 대상이다 (§8-5).
        if state.eraseTask?.phase == .flushing {
            return state.isFullyPersisted ? startArchive(state: &state) : .none
        }
        guard state.isSettledForReload else { return .none }
        // 보관 트랜잭션이 도는 중에는 재조회를 시작하지 않는다 — 끝난 뒤 `finishErase` 가 다시 합성한다.
        guard state.reloadWhenSettled, !state.isErasing else { return .none }
        return startReload(state: &state)
    }
}
