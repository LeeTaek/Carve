//
//  ChapterCanvasDraftFeature.swift
//  CarveFeature
//
//  편집마다 절 초안을 이 기기의 비동기화 영역에 남기고, 다시 불러올 때 겹친다 (정책 §12-6 구현 순서 ②).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 어느 장의 어느 절 — 초안 기준 · 이어받은 초안을 절마다 기억하는 키.
public struct DraftVerse: Hashable, Sendable {
    let chapter: BibleChapter
    let verse: Int
}

/// 절 편집을 시작할 때 보던 기준과 그 내용 지문. 초안은 이것을 들고 가, 다시 열 때 저장소 내용이 그대로인지 가린다.
struct DraftBase: Equatable, Sendable {
    let base: VerseEditBase
    let fingerprint: String?

    static let empty = DraftBase(base: .empty, fingerprint: nil)
}

/// 이 세션이 저장을 마친 초안 하나.
public struct DraftRecord: Equatable, Sendable {
    let key: VerseDraftKey
    let scope: AccountScope
    let revision: Int
}

/// 이 편집 세션의 초안 기록 (정책 §12-6 구현 순서 ②).
struct DraftSessionState: Equatable, Sendable {
    /// 초안 키의 세션. 첫 초안을 쓸 때 정한다.
    var sessionID: String?
    var status: DraftSaveStatus = .idle
    /// 절마다 이 세션이 편집을 시작할 때 보던 기준. 처음 편집할 때 `loadedBases` 에서 잡고 세션 동안 바꾸지 않는다.
    var bases: [DraftVerse: DraftBase] = [:]
    /// 마지막으로 불러온 저장소 내용(과 이어받은 초안)의 절 기준 — 아직 편집하지 않은 절의 기준 후보.
    var loadedBases: [DraftVerse: DraftBase] = [:]
    /// 행마다 이 세션이 초안으로 남긴 가장 새 revision.
    var records: [BibleDrawingRowID: DraftRecord] = [:]
    /// 행마다 저장소 저장까지 마친 가장 새 revision — 초안 정리의 근거.
    var storedRevisions: [BibleDrawingRowID: Int] = [:]
    /// 불러올 때 이어 보인 다른 세션의 초안. 이 세션이 그 절의 초안을 쓰면 이어받아 지운다.
    var adopted: [DraftVerse: VerseDraftKey] = [:]
    /// 저장소에 없고 초안에만 있는 행. 저장소에 쓸 때는 `replace` 가 아니라 `create` 로 보낸다.
    var draftOnlyRowIDs: Set<BibleDrawingRowID> = []
}

enum DraftSaveStatus: Equatable, Sendable {
    case idle
    case saving(requestID: UUID)
    /// 초안을 남기지 못했다. 성공 없이 이어진 실패 횟수를 든다.
    case failed(retryCount: Int)
}

/// 초안 저장 결과의 실패.
public enum DraftSaveFailure: Equatable, Sendable {
    /// 세션이 기댄 로컬 삭제 세대 뒤에 전체 삭제가 있었다. 그 편집은 삭제 전 내용 위에 쓴 것이다.
    case rejectedByErase
    /// 쓰지 못했다(공간 부족 · 초안 저장소 없음 등).
    case failed(String)
}

/// 남길 초안 하나 — 그 절과, 이어받아 지울 앞선 세션의 초안.
struct DraftSaveRequest: Sendable {
    let draft: VerseDraft
    let place: DraftVerse
    let superseding: [VerseDraftKey]
}

/// 저장을 마친 초안 하나 — 결과 액션에 싣는다.
public struct SavedDraft: Equatable, Sendable {
    let rowID: BibleDrawingRowID
    let place: DraftVerse
    let record: DraftRecord
}

extension ChapterCanvasFeature.State {
    /// 지금 세션의 편집을 저장소(`BibleDrawing`)에도 쓰는가. **소유가 확인된 유효 세션만** 쓴다 — 보존만 · 확인 대기 · K 를 읽지 못함이면
    /// 초안에만 남긴다. `BibleDrawing` 은 동기화되므로, 귀속할 근거가 없는 편집을 넣으면 다음에 확인되는 계정으로 올라간다(ACC-1 F30).
    var persistsToStore: Bool { sessionValidity == .valid }

    /// 초안이 **마지막 보존**인가 — 그러면 초안이 된 미저장분을 큐에서 내린다. 보존만 하는 세션과 닫는 중인 세션이다.
    /// 확인 대기는 아니다: 곧 같은 계정으로 확인되면 저장소에 써야 하므로 큐에 남겨 둔다.
    var draftsAreFinal: Bool {
        if sessionEnd != nil { return true }
        if case .preserveOnly = sessionValidity { return true }
        return false
    }

    var isSavingDrafts: Bool {
        if case .saving = drafts.status { return true }
        return false
    }

    /// 초안이 유일한 보존인데 남기지 못했으면 그 재시도 횟수. 저장소에도 쓰는 세션이면 저장 쪽 안내가 맡는다.
    var draftFailureCount: Int? {
        guard case .failed(let count) = drafts.status, draftsAreFinal || !persistsToStore else { return nil }
        return count
    }

    /// 성공 없이 이어진 초안 실패 횟수.
    var consecutiveDraftFailures: Int {
        if case .failed(let count) = drafts.status { return count }
        return 0
    }
}

extension ChapterCanvasFeature {
    // MARK: - 저장

    /// 아직 초안이 되지 않은 미저장분을 초안으로 남긴다. 한 번에 한 batch 만 — 끝나면 그 사이 들어온 편집을 이어 남긴다.
    ///
    /// 초안의 근거는 **편집한 세션의 것**이다 — 닫는 중이면 무효가 된 세션의 환경을 든다.
    func startDraftSaveIfPossible(state: inout State, allowRetry: Bool) -> Effect<Action> {
        if state.isSavingDrafts { return .none }
        if case .failed = state.drafts.status, !allowRetry { return .none }
        let waiting = state.pendingMutations.filter { rowID, entry in (state.drafts.records[rowID]?.revision ?? 0) < entry.revision }
        guard !waiting.isEmpty else { return .none }
        guard let writer = draftStore else {
            // 초안 저장소가 없다(주입하지 않음). 저장소에 쓰는 유효 세션이면 그쪽이 보존한다. 초안이 유일한 보존이면 실패로 알린다.
            if state.persistsToStore, !state.draftsAreFinal { return .none }
            Log.error("단일 Canvas — 초안 저장소가 없어 미저장분을 남기지 못했다", "count=\(waiting.count)")
            state.drafts.status = .failed(retryCount: state.consecutiveDraftFailures + 1)
            return state.sessionEnd == nil ? .none : failSessionEnd(state: &state, message: "초안 저장소 없음")
        }
        let sessionID = state.drafts.sessionID ?? uuid().uuidString
        state.drafts.sessionID = sessionID
        let environment = state.sessionEnd?.environment ?? state.editEnvironment
        let now = date.now
        let requests: [DraftSaveRequest] = waiting.values
            .sorted { lhs, rhs in
                (lhs.chapter.title.rawValue, lhs.chapter.chapter, lhs.mutation.verse) < (rhs.chapter.title.rawValue, rhs.chapter.chapter, rhs.mutation.verse)
            }
            .map { entry in
                let place = DraftVerse(chapter: entry.chapter, verse: entry.mutation.verse)
                let draft = Self.makeDraft(
                    entry, sessionID: sessionID, base: state.drafts.bases[place] ?? .empty, environment: environment, now: now
                )
                return DraftSaveRequest(draft: draft, place: place, superseding: state.drafts.adopted[place].map { [$0] } ?? [])
            }
        let requestID = uuid()
        state.drafts.status = .saving(requestID: requestID)
        return .run { send in
            var saved: [SavedDraft] = []
            for request in requests {
                let draft = request.draft
                do {
                    let outcome = try await writer.saveDraft(draft, superseding: request.superseding)
                    if case .rejectedByErase = outcome {
                        await send(.draftsSaved(requestID: requestID, saved: saved, failure: .rejectedByErase))
                        return
                    }
                    saved.append(SavedDraft(
                        rowID: draft.rowID,
                        place: request.place,
                        record: DraftRecord(key: draft.key, scope: draft.account.preservationScope, revision: draft.revision)
                    ))
                } catch {
                    await send(.draftsSaved(requestID: requestID, saved: saved, failure: .failed("\(error)")))
                    return
                }
            }
            await send(.draftsSaved(requestID: requestID, saved: saved, failure: nil))
        }
    }

    /// 초안 저장의 결과. 지금 도는 저장의 응답만 받는다.
    func finishDraftSave(state: inout State, requestID: UUID, saved: [SavedDraft], failure: DraftSaveFailure?) -> Effect<Action> {
        guard case .saving(let current) = state.drafts.status, current == requestID else {
            Log.error("단일 Canvas — 지금 도는 초안 저장이 아닌 응답을 버린다", "saved=\(saved.count)")
            return .none
        }
        // 일부만 저장하고 실패했어도 저장한 것은 기록한다 — 다시 할 때 그만큼 덜 쓴다.
        for item in saved {
            let previous = state.drafts.records[item.rowID]?.revision ?? 0
            if item.record.revision >= previous { state.drafts.records[item.rowID] = item.record }
            // 이어받은 다른 세션의 초안은 이 초안을 쓰면서 지웠다.
            state.drafts.adopted[item.place] = nil
        }
        switch failure {
        case .rejectedByErase:
            // 사용자가 이 기기의 필사 데이터를 전부 지웠다 — 삭제 전 내용 위의 편집이다. 설정의 삭제 알림과 같은 정리를 한다.
            Log.error("단일 Canvas — 초안이 전체 삭제 세대에 걸려 거절됐다. 미저장분을 버리고 다시 읽는다")
            state.drafts.status = .idle
            return clearAfterExternalDelete(state: &state)
        case .failed(let message):
            Log.error("단일 Canvas — 초안을 남기지 못했다. 미저장분은 큐에 남긴다", message)
            state.drafts.status = .failed(retryCount: state.consecutiveDraftFailures + 1)
            return state.sessionEnd == nil ? .none : failSessionEnd(state: &state, message: message)
        case nil:
            state.drafts.status = .idle
        }
        var effects: [Effect<Action>] = []
        if state.draftsAreFinal {
            // 초안이 곧 보존이다 — 초안이 된 revision 의 미저장분을 큐에서 내리고, 화면의 근거(loadedDrawings)에 겹친다.
            dropDraftedPending(state: &state)
        } else {
            effects.append(releaseStoredDrafts(state: &state))
        }
        effects.append(startDraftSaveIfPossible(state: &state, allowRetry: false))
        if state.sessionEnd != nil {
            // 닫기를 잇는다 — 인계를 기다리는 중이면 `continueSessionEnd` 가 그대로 둔다(뷰의 마지막 보고를 받아야 한다).
            effects.append(continueSessionEnd(state: &state))
        } else {
            effects.append(settleIfNeeded(state: &state))
        }
        return .merge(effects)
    }

    /// 저장소 저장까지 마친 revision 의 초안을 지운다 — 로컬 확정을 확인한 뒤에만 초안을 완료로 처리한다(정책 §12-3).
    func releaseStoredDrafts(state: inout State) -> Effect<Action> {
        let releasable = state.drafts.records.filter { rowID, record in (state.drafts.storedRevisions[rowID] ?? 0) >= record.revision }
        guard !releasable.isEmpty, let writer = draftStore else { return .none }
        for rowID in releasable.keys { state.drafts.records[rowID] = nil }
        let records = Array(releasable.values)
        return .run { _ in
            for record in records {
                do {
                    try await writer.removeDraft(record.key, scope: record.scope, ifRevision: record.revision)
                } catch {
                    // 남아도 잃는 것은 없다 — 다음에 불러올 때 같은 내용이면 정리 대상이다.
                    Log.error("단일 Canvas — 저장을 마친 초안을 지우지 못했다", "\(error)")
                }
            }
        }
    }

    static func makeDraft(
        _ entry: PendingDrawingMutation,
        sessionID: String,
        base: DraftBase,
        environment: DrawingEditEnvironment,
        now: Date
    ) -> VerseDraft {
        // 편집은 늘 현재 레이아웃 기준 v3 로 저장된다(`DrawingCodec.mutations`). 비운 절은 내용이 없다.
        var lineData: Data?
        var metadataBlob: Data?
        if case .create(_, _, let data, let metadata) = entry.mutation {
            lineData = data
            metadataBlob = try? metadata.encodedBlob()
        } else if case .replace(_, _, let data, let metadata) = entry.mutation {
            lineData = data
            metadataBlob = try? metadata.encodedBlob()
        }
        return VerseDraft(
            key: VerseDraftKey(sessionID: sessionID, chapter: entry.chapter, verse: entry.mutation.verse),
            revision: entry.revision,
            rowID: entry.mutation.rowID,
            lineData: lineData,
            drawingVersion: lineData == nil ? nil : 3,
            layoutMetadataData: metadataBlob,
            base: base.base,
            baseFingerprint: base.fingerprint,
            account: environment.accountBasis,
            knownEpochs: environment.knowledge?.all,
            storeOwnership: environment.storeOwnership,
            eraseGeneration: environment.eraseGeneration,
            savedAt: now
        )
    }

    // MARK: - 세션

    /// 새 편집 세션 — 근거가 바뀌어 다시 열 때. 이전 세션의 초안은 그 세션의 출처를 단 채 남고, 다음 조회에서 다른 세션의 초안으로 판정된다.
    /// 세션 ID 는 첫 초안을 쓸 때 정한다.
    func resetDraftSession(state: inout State) {
        state.drafts = DraftSessionState()
        state.sessionValidity = Self.sessionValidity(session: state.editEnvironment, latest: state.editEnvironment)
    }

    // MARK: - 복구

    /// 그 환경의 계정 근거 묶음에 남은 이 장의 초안. 읽지 못해도 조회는 잇는다 — 초안은 지워지지 않고 다음에 다시 읽힌다.
    static func readDrafts(from store: (any VerseDraftStore)?, environment: DrawingEditEnvironment, chapter: BibleChapter) async -> [VerseDraft] {
        guard let store else { return [] }
        do {
            return try await store.drafts(in: environment.accountBasis.preservationScope, chapter: chapter, translation: .NKRV)
        } catch {
            Log.error("단일 Canvas — 이 장의 초안을 읽지 못했다. 저장소 내용만으로 합성한다", "\(error)")
            return []
        }
    }

    /// 조회한 저장소 내용 위에 남은 초안을 겹친다 — 지금 세션의 초안과, 이어 써도 되는 다른 세션의 초안(`VerseDraftRecoveryRule`).
    /// 이 장의 절 기준도 여기서 잡는다. 이미 편집한 절의 기준은 바꾸지 않는다(`drafts.bases`).
    /// - Returns: 겹친 내용과, 이미 저장소에 있는 초안을 정리하는 효과.
    func recoverDrafts(state: inout State, snapshots: [VerseDrawingSnapshot], drafts: [VerseDraft]) -> ([VerseDrawingSnapshot], Effect<Action>) {
        let chapter = state.chapter
        var representatives: [Int: VerseDrawingSnapshot] = [:]
        var storeContent: [Int: String] = [:]
        for (verse, rows) in Dictionary(grouping: snapshots, by: \.verse) {
            guard let representative = rows.representative() else { continue }
            representatives[verse] = representative
            if let fingerprint = Self.contentFingerprint(representative) { storeContent[verse] = fingerprint }
        }
        // 저장소 내용 그대로의 기준 — 아직 편집하지 않은 절이 편집을 시작하면 이것을 든다.
        for (verse, representative) in representatives {
            let fingerprint = storeContent[verse]
            state.drafts.loadedBases[DraftVerse(chapter: chapter, verse: verse)] = fingerprint.map {
                DraftBase(base: .legacy(rowID: representative.rowID, contentFingerprint: $0), fingerprint: $0)
            } ?? .empty
        }
        let plan = VerseDraftRecoveryRule.plan(
            drafts: drafts, storeContent: storeContent, environment: state.editEnvironment, sessionID: state.drafts.sessionID
        )
        var mutations: [VerseDrawingMutation] = []
        for draft in plan.shown {
            let verse = draft.key.verse
            let place = DraftVerse(chapter: chapter, verse: verse)
            let representative = representatives[verse]
            let rowID = representative?.rowID ?? draft.rowID
            if draft.key.sessionID != state.drafts.sessionID {
                // 다른 세션의 초안을 이어 보인다 — 이 절을 다시 편집하면 그 초안을 이어받아 지운다. 기준은 그 초안의 것이다.
                state.drafts.adopted[place] = draft.key
                state.drafts.loadedBases[place] = DraftBase(base: draft.base, fingerprint: draft.baseFingerprint)
            }
            guard let data = draft.lineData else {
                mutations.append(.clear(verse: verse, rowID: rowID))
                continue
            }
            guard let metadata = DrawingLayoutMetadata.decode(blob: draft.layoutMetadataData) else {
                Log.error("단일 Canvas — 초안의 좌표 정보를 읽지 못해 겹치지 않는다(초안은 남김)", "verse=\(verse)")
                state.drafts.adopted[place] = nil
                continue
            }
            if representative == nil {
                state.drafts.draftOnlyRowIDs.insert(rowID)
                mutations.append(.create(verse: verse, rowID: rowID, data: data, metadata: metadata))
            } else {
                mutations.append(.replace(verse: verse, rowID: rowID, data: data, metadata: metadata))
            }
        }
        if !plan.kept.isEmpty {
            Log.info("단일 Canvas — 보이지 않고 남긴 초안", "chapter=\(chapter.title.rawValue).\(chapter.chapter)", "count=\(plan.kept.count)")
        }
        let settled = plan.settled
        let cleanup: Effect<Action> = settled.isEmpty || draftStore == nil ? .none : .run { [writer = draftStore] _ in
            for draft in settled {
                try? await writer?.removeDraft(draft.key, scope: draft.account.preservationScope, ifRevision: draft.revision)
            }
        }
        return (overlay(snapshots, with: mutations), cleanup)
    }

    /// 저장소 행의 내용 지문. 비운 행이면 nil — 빈 절과 같다.
    static func contentFingerprint(_ snapshot: VerseDrawingSnapshot) -> String? {
        guard let lineData = snapshot.lineData else { return nil }
        return VerseContentFingerprint.make(
            lineData: lineData, drawingVersion: snapshot.drawingVersion, layoutMetadataBlob: try? snapshot.metadata?.encodedBlob()
        )
    }
}
