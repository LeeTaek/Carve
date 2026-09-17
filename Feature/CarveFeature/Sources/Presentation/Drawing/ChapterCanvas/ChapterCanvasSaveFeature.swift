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
        if case .saving = saveStatus { return .saving }
        if hasUnsavedChanges { return .pending }
        // 마지막으로 전부 지운 뒤에 쓴 것이 있을 때만. 이전 구현은 `editRevision > 0` 만 봐서
        // 필사를 전부 지운 직후에도 "이 기기에 저장됨" 이 떴다.
        return editRevision > editRevisionAtClear ? .saved : .none
    }

    /// 아직 저장하지 않은 변경이 있는가. **장과 무관하다** — 장을 바꿔도 남은 이전 장의 미저장분을 포함한다.
    ///
    /// 획을 긋는 중(`isEditing`)도 포함한다. 그 획은 아직 보고되지도 않았으므로 저장됐다고 말할 수 없다.
    var hasUnsavedChanges: Bool {
        isEditing || isPreparingEdit || !editQueue.isEmpty || !pendingMutations.isEmpty
    }

    /// 저장에 실패해 **사용자에게 알려야 하는** 상태면 지금까지의 재시도 횟수. 아니면 nil.
    ///
    /// 실패해도 큐는 보존되고 다음 편집·flush 에서 자동으로 다시 시도한다(§8-4). 그래도 알리는 이유는
    /// 그 재시도가 언제 일어날지 사용자가 알 수 없고, **그 사이에 앱을 닫으면 미저장분이 사라지기** 때문이다.
    var saveRetryCount: Int? {
        guard case .failed(_, let count) = saveStatus else { return nil }
        return count
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
    func startSaveIfPossible(state: inout State, allowRetry: Bool) -> Effect<Action> {
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
        let requestID = uuid()
        state.saveStatus = .saving(revision: revision, requestID: requestID)

        return .run { [repository] send in
            do {
                try await repository.apply(mutations, chapter: chapter)
                await send(.saveFinished(requestID: requestID, revision: revision, failure: nil))
            } catch let error as DrawingRepositoryError {
                await send(.saveFinished(requestID: requestID, revision: revision, failure: error))
            } catch {
                await send(.saveFinished(requestID: requestID, revision: revision, failure: .persistenceFailed("\(error)")))
            }
        }
    }

    func finishSave(state: inout State, requestID: UUID, revision: Int, failure: DrawingRepositoryError?) -> Effect<Action> {
        // ★ 지금 도는 저장의 응답인가. 이전 구현은 이것을 보지 않고 **현재의** 진행 중 기록을 가져가 처리해서,
        //   전체 삭제로 상태를 비운 뒤 시작한 새 저장이 있을 때 삭제 전 저장의 늦은 응답이 그 새 필사를 큐에서 지웠다.
        //   진행 중 기록은 이 저장의 것이 아니므로 건드리지 않는다.
        guard case .saving(_, let current) = state.saveStatus, current == requestID else {
            Log.error("단일 Canvas — 지금 도는 저장이 아닌 완료 응답을 버린다", "revision=\(revision)", "failure=\(String(describing: failure))")
            return .none
        }
        let batch = state.inFlightBatch
        let mutations = state.inFlightMutations
        let chapter = state.inFlightChapter
        state.inFlightBatch = [:]
        state.inFlightMutations = []
        state.inFlightChapter = nil

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
        // 저장된 내용을 DB 내용에 겹쳐 둔다 — 재조회가 실패해도 `loadedDrawings ⊕ pendingMutations` 가 현재 내용이 되게.
        if chapter == state.chapter, let loaded = state.loadedDrawings {
            state.loadedDrawings = overlay(loaded, with: mutations)
        }
        state.persistedRevision = max(state.persistedRevision, revision)
        state.consecutiveSaveFailures = 0
        state.saveStatus = .idle
        return startSaveIfPossible(state: &state, allowRetry: false)
    }

    /// 저장할 것이 없을 때 — 지우기가 기다리고 있으면 지금 보관하고, 아니면 예약된 재합성을 지금 읽는다.
    func settleIfNeeded(state: inout State) -> Effect<Action> {
        guard state.isFullyPersisted else { return .none }
        // 지우기가 재합성보다 앞선다. flush 가 끝난 **지금**의 DB 가 "방금까지 쓴 내용" 이고, 그것이 보관 대상이다 (§8-5).
        if state.eraseTask?.phase == .flushing {
            return startArchive(state: &state)
        }
        // 보관 트랜잭션이 도는 중에는 재조회를 시작하지 않는다 — 끝난 뒤 `finishErase` 가 다시 합성한다.
        guard state.reloadWhenSettled, !state.isErasing else { return .none }
        return startReload(state: &state)
    }
}
