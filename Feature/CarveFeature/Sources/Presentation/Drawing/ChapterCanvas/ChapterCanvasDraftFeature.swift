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
    /// 이 기기 안에서 초안 세션을 가르는 번호. 세션을 새로 열 때마다 오른다 — 편집 문맥(`EditSession.draftEpoch`)이 이 값으로 자기 세션을
    /// 가리켜, 세션이 바뀐 뒤 늦게 온 편집을 닫은 세션의 초안으로 보낸다(`finishLateEdit`).
    var epoch = 0
    /// 초안 키의 세션. 첫 초안을 쓸 때 정한다.
    var sessionID: String?
    var status: DraftSaveStatus = .idle
    /// 절마다 이 세션이 편집을 시작할 때 보던 기준. 처음 편집할 때 `loadedBases` 에서 잡고 세션 동안 바꾸지 않는다.
    var bases: [DraftVerse: DraftBase] = [:]
    /// 마지막으로 불러온 저장소 내용(과 이어 보인 초안)의 절 기준 — 아직 편집하지 않은 절의 기준 후보.
    var loadedBases: [DraftVerse: DraftBase] = [:]
    /// 행마다 이 세션이 초안으로 남긴 가장 새 revision.
    var records: [BibleDrawingRowID: DraftRecord] = [:]
    /// 행마다 저장소 저장까지 마친 가장 새 revision — 그 revision 까지의 이 세션 초안은 역할이 끝났다(다시 읽을 때 겹치지 않는다).
    /// **초안을 지우는 근거가 아니다** — 로컬 저장은 보존이 아니다(ACC-1 F29). 정리는 ③ 의 확정이 한다.
    var storedRevisions: [BibleDrawingRowID: Int] = [:]
    /// 불러올 때 이어 보인 다른 세션의 초안과 그 revision. 이 세션이 그 절의 초안을 쓰면 이어받아 지운다 — 보인 그 revision 일 때만, 보이기만
    /// 하던 초안이면 출처가 그대로 이어질 때만.
    var adopted: [DraftVerse: VerseDraftRef] = [:]
    /// 보이기만 하는 초안(`VerseDraftRecoveryPlan.showOnly`)을 이어 보인 절과 그 출처. 그 절의 편집은 지금 세션이 아니라 이 출처로 초안이 되고
    /// **저장소에 쓰지 않는다** — 한 획을 더한 것은 계정 간 가져오기 동의가 아니다(④ 의 명시적 가져오기 전까지).
    var inherited: [DraftVerse: VerseDraftProvenance] = [:]
    /// 저장소에 없고 초안에만 있는 행. 저장소에 쓸 때는 `replace` 가 아니라 `create` 로 보낸다.
    var draftOnlyRowIDs: Set<BibleDrawingRowID> = []
    /// 절마다 **자동으로 표시되지 않고 남은** 초안 수(`VerseDraftRecoveryPlan.kept` — 표시 실패 포함). 절 메뉴가 「남은 필기 N」 을 띄울
    /// 근거다 — 복구 화면(④)이 그 절에서 보일 것과 같은 수다. 불러올 때마다 다시 센다.
    var hiddenCounts: [Int: Int] = [:]
    /// 이 장에서 자동으로 표시되지 않고 남은 초안 — 도착한 필사의 「확인하기」 뒤 새로 감춰진 것을 센다(P0-3).
    var hiddenKeys: Set<VerseDraftKey> = []
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

/// 남길 초안 하나 — 그 절과, 이어받아 지울 앞선 세션의 초안(그 revision).
struct DraftSaveRequest: Sendable {
    let draft: VerseDraft
    let place: DraftVerse
    let superseding: [VerseDraftRef]
    /// 닫은 세션의 늦은 편집이면 그 키.
    let late: LateDraftKey?
}

/// 저장을 마친 초안 하나 — 결과 액션에 싣는다.
public struct SavedDraft: Equatable, Sendable {
    let rowID: BibleDrawingRowID
    let place: DraftVerse
    let record: DraftRecord
    /// 닫은 세션의 늦은 편집이면 그 키.
    var late: LateDraftKey?
}

// MARK: - 닫은 세션

/// 닫은 초안 세션의 늦은 편집을 가리키는 키 — 그 세션(`DraftSessionState.epoch`)과 행.
public struct LateDraftKey: Hashable, Sendable {
    let epoch: Int
    let rowID: BibleDrawingRowID
}

/// 닫은 초안 세션의 출처 — 인계를 마친 뒤 늦게 온 그 세션의 편집을 그 세션의 초안으로 남기려고 기억한다.
struct ClosedDraftSession: Equatable, Sendable {
    /// 초안 키의 세션. 그 세션이 초안을 쓰기 전에 닫혔으면 nil — 늦은 편집이 처음 초안이 될 때 정한다.
    var sessionID: String?
    /// 그 세션이 기댄 환경.
    let environment: DrawingEditEnvironment
    /// 절마다 그 세션이 보던 기준.
    let bases: [DraftVerse: DraftBase]
    /// 그 세션에서 보이기만 하는 초안을 이은 절의 출처.
    let inherited: [DraftVerse: VerseDraftProvenance]
}

/// 닫은 초안 세션들과 그 늦은 편집 (정책 §12-6 구현 순서 ②).
struct ClosedDraftSessions: Equatable, Sendable {
    var sessions: [Int: ClosedDraftSession] = [:]
    /// 닫은 세션들의 편집 문맥(현재 세대 · 물러난 세대). 늦은 편집은 이 문맥으로 계산한다. 붙은 캔버스가 모두 더 새 세대를 표시하고 큐가 그 세대의
    /// 편집을 들고 있지 않을 때까지 둔다(`pruneClosedContexts`) — 연달아 바뀌어도(A → B → A) 첫 세션의 늦은 보고를 계산할 수 있다.
    var contexts: [EditSession] = []
    /// 아직 초안이 되지 않은 늦은 편집. 초안이 되면 내린다 — 저장소에는 쓰지 않는다.
    var pending: [LateDraftKey: PendingDrawingMutation] = [:]

    /// 늦은 편집을 받을 문맥도, 초안으로 남길 늦은 편집도 없는 세션을 잊는다.
    mutating func prune() {
        let live = Set(contexts.map(\.draftEpoch)).union(pending.keys.map(\.epoch))
        sessions = sessions.filter { live.contains($0.key) }
    }
}

// MARK: - 저장소로 가는가

extension ChapterCanvasFeature.State {
    /// 지금 세션의 편집을 저장소(`BibleDrawing`)에도 쓰는가. **소유가 확인된 유효 세션만** 쓴다 — 보존만 · 확인 대기 · K 를 읽지 못함이면
    /// 초안에만 남긴다. `BibleDrawing` 은 동기화되므로, 귀속할 근거가 없는 편집을 넣으면 다음에 확인되는 계정으로 올라간다(ACC-1 F30).
    /// 로그인하지 않은 세션도 같다 — 이 기기 전용 문맥으로는 유효하지만 소유 근거가 없고, 미러링은 그 행을 다음에 로그인한 계정으로 올린다.
    var persistsToStore: Bool { sessionValidity == .valid && editEnvironment.storeOwnership != nil }

    /// 계정을 다시 확인하는 동안 미저장분을 큐에 붙잡아 두는가 — 같은 계정으로 확인되면 저장소에 쓸 세션이다. 소유 근거가 없던 세션은
    /// 확인돼도 쓰지 않으므로 붙잡지 않는다.
    var holdsForStore: Bool { sessionValidity == .awaitingAccountConfirmation && editEnvironment.storeOwnership != nil }

    /// 이 미저장분이 저장소로 갈 수 있는가(지금 또는 계정 확인 뒤). 닫는 세션의 것, 보이기만 하는 초안을 이은 절의 것은 가지 않는다 —
    /// 그런 미저장분은 초안이 곧 보존이라 초안이 되면 큐에서 내린다(`dropDraftedPending`).
    func mayReachStore(_ entry: PendingDrawingMutation) -> Bool {
        guard sessionEnd == nil, persistsToStore || holdsForStore else { return false }
        return drafts.inherited[DraftVerse(chapter: entry.chapter, verse: entry.mutation.verse)] == nil
    }

    /// 지금 저장소에 쓸 미저장분인가.
    func isStoreBound(_ entry: PendingDrawingMutation) -> Bool {
        persistsToStore && mayReachStore(entry)
    }

    /// 그 절의 지금 필기가 **다른 출처**인가 — 보이기만 하는 초안(다른 계정 · 확인 전)을 이어 보고 있다. 그 잉크를 즐겨찾기 · 위젯처럼
    /// 동기화되는 다른 저장소로 옮기면 계정 간 가져오기가 된다(11차 리뷰 P0-2).
    func inheritsOtherSessionInk(verse: Int) -> Bool {
        drafts.inherited[DraftVerse(chapter: chapter, verse: verse)] != nil
    }

    /// 이 장의 그 절을 지금 저장소에 쓰는가 — 지우기 · 기록 복원처럼 저장소 행을 바로 바꾸는 일의 게이트.
    func writesStore(verse: Int) -> Bool {
        persistsToStore && sessionEnd == nil && drafts.inherited[DraftVerse(chapter: chapter, verse: verse)] == nil
    }

    /// 그 revision 까지 초안이 됐는가.
    func isDrafted(_ rowID: BibleDrawingRowID, _ entry: PendingDrawingMutation) -> Bool {
        (drafts.records[rowID]?.revision ?? 0) >= entry.revision
    }

    var isSavingDrafts: Bool {
        if case .saving = drafts.status { return true }
        return false
    }

    /// 초안을 남기지 못했으면 그 재시도 횟수. 초안이 되지 않은 미저장분은 저장소에도 가지 않는다(초안이 먼저다) — 그대로 두고 앱을 닫으면
    /// 사라지므로 알린다.
    var draftFailureCount: Int? {
        guard case .failed(let count) = drafts.status else { return nil }
        let undrafted = !closedDrafts.pending.isEmpty || pendingMutations.contains { rowID, entry in !isDrafted(rowID, entry) }
        return undrafted ? count : nil
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
    /// 초안의 근거는 **편집한 세션의 것**이다 — 닫는 중이면 무효가 된 세션의 환경을, 보이기만 하는 초안을 이은 절이면 그 초안의 출처를,
    /// 닫은 세션의 늦은 편집이면 그 세션의 것을 든다.
    func startDraftSaveIfPossible(state: inout State, allowRetry: Bool) -> Effect<Action> {
        if state.isSavingDrafts { return .none }
        if case .failed = state.drafts.status, !allowRetry { return .none }
        let waiting = state.pendingMutations.filter { !state.isDrafted($0.key, $0.value) }
        let late = state.closedDrafts.pending
        guard !waiting.isEmpty || !late.isEmpty else { return .none }
        guard let writer = draftStore else {
            // 초안 저장소가 없다(주입하지 않음). 저장소에 쓸 미저장분이면 그쪽이 보존한다. 초안이 유일한 보존인 것이 있으면 실패로 알린다.
            if late.isEmpty, waiting.values.allSatisfy({ state.isStoreBound($0) }) { return .none }
            Log.error("단일 Canvas — 초안 저장소가 없어 미저장분을 남기지 못했다", "count=\(waiting.count + late.count)")
            state.drafts.status = .failed(retryCount: state.consecutiveDraftFailures + 1)
            return state.sessionEnd == nil ? .none : failSessionEnd(state: &state, message: "초안 저장소 없음")
        }
        let now = date.now
        let requests = currentDraftRequests(state: &state, waiting: waiting, now: now) + lateDraftRequests(state: &state, late: late, now: now)
        guard !requests.isEmpty else { return .none }
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
                        record: DraftRecord(key: draft.key, scope: draft.account.preservationScope, revision: draft.revision),
                        late: request.late
                    ))
                } catch {
                    await send(.draftsSaved(requestID: requestID, saved: saved, failure: .failed("\(error)")))
                    return
                }
            }
            await send(.draftsSaved(requestID: requestID, saved: saved, failure: nil))
        }
    }

    /// 지금 세션의 미저장분으로 남길 초안들.
    private func currentDraftRequests(
        state: inout State,
        waiting: [BibleDrawingRowID: PendingDrawingMutation],
        now: Date
    ) -> [DraftSaveRequest] {
        guard !waiting.isEmpty else { return [] }
        let sessionID = state.drafts.sessionID ?? uuid().uuidString
        state.drafts.sessionID = sessionID
        let environment = state.sessionEnd?.environment ?? state.editEnvironment
        let drafts = state.drafts
        let current = state
        return waiting.values.sorted(by: Self.draftOrder).map { entry in
            let place = DraftVerse(chapter: entry.chapter, verse: entry.mutation.verse)
            let inherited = drafts.inherited[place]
            // 저장소로 갈 수 있는 revision 은 "보내는 중" 표식과 함께 남긴다 — 저장소 쓰기는 이 초안이 남은 뒤에만 한다.
            let draft = Self.makeDraft(
                entry, sessionID: sessionID, base: drafts.bases[place] ?? .empty,
                provenance: inherited ?? environment.draftProvenance, eraseGeneration: environment.eraseGeneration, now: now,
                storeState: current.mayReachStore(entry) ? .sending : nil
            )
            // 이어 보인 초안을 대신한다. 보이기만 하던 초안이면 새 초안이 그 출처를 그대로 이을 때만 — 원 초안이 출처를 잃은 채 지워지지 않게.
            let superseding = drafts.adopted[place].map { ref in inherited == nil || inherited == draft.provenance ? [ref] : [] } ?? []
            return DraftSaveRequest(draft: draft, place: place, superseding: superseding, late: nil)
        }
    }

    /// 닫은 세션의 늦은 편집으로 남길 초안들 — 그 세션의 ID · 근거 · 기준을 든다. 그 세션의 같은 절 초안을 더 새 revision 으로 잇는다.
    private func lateDraftRequests(
        state: inout State,
        late: [LateDraftKey: PendingDrawingMutation],
        now: Date
    ) -> [DraftSaveRequest] {
        var requests: [DraftSaveRequest] = []
        for (key, entry) in late.sorted(by: { Self.draftOrder($0.value, $1.value) }) {
            guard var closed = state.closedDrafts.sessions[key.epoch] else {
                Log.error("단일 Canvas — 늦은 편집의 닫은 세션을 찾지 못했다. 초안으로 남기지 못한다", "epoch=\(key.epoch)")
                continue
            }
            let sessionID = closed.sessionID ?? uuid().uuidString
            closed.sessionID = sessionID
            state.closedDrafts.sessions[key.epoch] = closed
            let place = DraftVerse(chapter: entry.chapter, verse: entry.mutation.verse)
            let draft = Self.makeDraft(
                entry, sessionID: sessionID, base: closed.bases[place] ?? .empty,
                provenance: closed.inherited[place] ?? closed.environment.draftProvenance,
                eraseGeneration: closed.environment.eraseGeneration, now: now
            )
            requests.append(DraftSaveRequest(draft: draft, place: place, superseding: [], late: key))
        }
        return requests
    }

    private static func draftOrder(_ lhs: PendingDrawingMutation, _ rhs: PendingDrawingMutation) -> Bool {
        (lhs.chapter.title.rawValue, lhs.chapter.chapter, lhs.mutation.verse) < (rhs.chapter.title.rawValue, rhs.chapter.chapter, rhs.mutation.verse)
    }

    /// 초안 저장의 결과. 지금 도는 저장의 응답만 받는다.
    func finishDraftSave(state: inout State, requestID: UUID, saved: [SavedDraft], failure: DraftSaveFailure?) -> Effect<Action> {
        guard case .saving(let current) = state.drafts.status, current == requestID else {
            Log.error("단일 Canvas — 지금 도는 초안 저장이 아닌 응답을 버린다", "saved=\(saved.count)")
            return .none
        }
        // 일부만 저장하고 실패했어도 저장한 것은 기록한다 — 다시 할 때 그만큼 덜 쓴다.
        for item in saved {
            if let key = item.late {
                // 닫은 세션의 늦은 편집이 초안이 됐다. 그 사이 더 새 늦은 편집이 왔으면 남긴다.
                if state.closedDrafts.pending[key]?.revision == item.record.revision { state.closedDrafts.pending[key] = nil }
                continue
            }
            let previous = state.drafts.records[item.rowID]?.revision ?? 0
            if item.record.revision >= previous { state.drafts.records[item.rowID] = item.record }
            // 이어받은 다른 세션의 초안은 이 초안을 쓰면서 지웠다(또는 출처가 달라 남겼다). 어느 쪽이든 다시 이어받지 않는다.
            state.drafts.adopted[item.place] = nil
        }
        state.closedDrafts.prune()
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
        // 초안이 곧 보존인 미저장분(저장소로 가지 않는 것)은 큐에서 내리고 화면의 근거에 겹친다. 저장소로 갈 미저장분은 남긴다 — 그 저장을
        // 마쳐도 초안은 지우지 않는다(ACC-1 F29: 전송 전에 계정이 바뀌면 미러링이 그 행을 지우고 되살리지 않는다).
        dropDraftedPending(state: &state)
        var effects = [markStoredDrafts(state: state, rows: saved.filter { $0.late == nil }.map(\.rowID))]
        if state.sessionEnd != nil {
            // 닫기를 잇는다 — 인계를 기다리는 중이면 `continueSessionEnd` 가 그대로 둔다(뷰의 마지막 보고를 받아야 한다).
            effects.append(startDraftSaveIfPossible(state: &state, allowRetry: false))
            effects.append(continueSessionEnd(state: &state))
        } else {
            // 초안이 된 revision 은 이제 저장소로 보낼 수 있다(초안이 먼저다). 편집마다 저장을 다시 시도하던 것과 같게 실패했던 저장도 다시 한다.
            effects.append(startSaveIfPossible(state: &state, allowRetry: true))
        }
        return .merge(effects)
    }

    /// 저장소 저장을 마친 revision 의 초안에 "들어감" 표식을 남긴다(`VerseDraft.storeState = .stored`). 초안은 저장소 쓰기보다 먼저 "보내는 중"
    /// 으로 남았으므로, 표식을 남기지 못해도(그 사이 종료 · 쓰기 실패) 다음 세션은 그 초안을 저장 완료가 불확실한 것으로 다룬다 — 기준이 같다는
    /// 이유로 확정된 사실처럼 되살리지 않는다.
    /// - Parameter sent: 방금 저장소에 **실제로 넣은 내용**의 지문(행마다). 초안 파일이 그 사이 더 새 revision 이어도 이 지문은 남는다 —
    ///   그 행이 나중에 이 내용으로 돌아오면 그 뒤 편집이 전송되지 않은 것이다(11차 리뷰 P1).
    func markStoredDrafts(state: State, rows: [BibleDrawingRowID], sent: [BibleDrawingRowID: String] = [:]) -> Effect<Action> {
        let marks: [(record: DraftRecord, sent: String?)] = rows.compactMap { rowID in
            guard let record = state.drafts.records[rowID], let stored = state.drafts.storedRevisions[rowID],
                  record.revision <= stored else { return nil }
            return (DraftRecord(key: record.key, scope: record.scope, revision: stored), sent[rowID])
        }
        guard !marks.isEmpty, let writer = draftStore else { return .none }
        return .run { _ in
            for mark in marks {
                do {
                    try await writer.markDraftStored(
                        mark.record.key, scope: mark.record.scope, throughRevision: mark.record.revision, contentFingerprint: mark.sent
                    )
                } catch {
                    Log.error("단일 Canvas — 저장소에 넣은 초안에 표식을 남기지 못했다(초안은 남는다)", "\(error)")
                }
            }
        }
    }

    /// 저장소에 넣은 그 명령의 내용 지문. 비운 절(`clear`)은 지문이 없다.
    static func sentFingerprint(of mutation: VerseDrawingMutation) -> String? {
        switch mutation {
        case let .create(_, _, data, metadata), let .replace(_, _, data, metadata):
            VerseContentFingerprint.make(lineData: data, drawingVersion: 3, layoutMetadataBlob: try? metadata.encodedBlob())
        case .clear:
            nil
        }
    }

    /// 초안이 곧 보존인 미저장분(`mayReachStore` 가 거짓) 가운데 그 revision 까지 초안이 된 것을 큐에서 내리고 화면의 근거에 겹친다 —
    /// 닫는 세션 · 보존만 · 로그인하지 않은 세션의 미저장분과, 보이기만 하는 초안을 이은 절의 미저장분이다.
    func dropDraftedPending(state: inout State) {
        for (rowID, entry) in state.pendingMutations where state.isDrafted(rowID, entry) && !state.mayReachStore(entry) {
            state.pendingMutations[rowID] = nil
            if case .create = entry.mutation { state.drafts.draftOnlyRowIDs.insert(rowID) }
            if entry.chapter == state.chapter, let loaded = state.loadedDrawings {
                state.loadedDrawings = overlay(loaded, with: [entry.mutation])
            }
        }
    }

    static func makeDraft(
        _ entry: PendingDrawingMutation,
        sessionID: String,
        base: DraftBase,
        provenance: VerseDraftProvenance,
        eraseGeneration: UInt64,
        now: Date,
        storeState: VerseDraftStoreState? = nil
    ) -> VerseDraft {
        // 편집은 늘 현재 레이아웃 기준 v3 로 저장된다(`DrawingCodec.mutations`). 비운 절은 내용이 없다.
        var lineData: Data?
        var metadataBlob: Data?
        if case .create(let verse, _, let data, let metadata) = entry.mutation {
            lineData = data
            metadataBlob = draftMetadataBlob(metadata, verse: verse)
        } else if case .replace(let verse, _, let data, let metadata) = entry.mutation {
            lineData = data
            metadataBlob = draftMetadataBlob(metadata, verse: verse)
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
            account: provenance.account,
            knownEpochs: provenance.knownEpochs,
            storeOwnership: provenance.storeOwnership,
            eraseGeneration: eraseGeneration,
            savedAt: now,
            storeState: storeState,
            ownershipInjected: provenance.ownershipInjected
        )
    }

    /// 초안에 남길 좌표 정보. **인코딩하지 못해도 잉크는 남긴다** — 그 획의 사본은 이 초안뿐일 수 있다(초안이 먼저다). 그런 초안은 겹칠 수 없어
    /// 캔버스 · 「남은 필기」 가 같은 판정(`VerseDraftRecoveryRule.isDisplayable`)으로 **표시 실패**로 알린다. 조용히 넘기지 않는다(2026-09-21
    /// 후속 리뷰 P0-2b — 예전에는 `try?` 로 좌표 없는 초안이 생겨도 기록이 없었고, 그 초안은 어디에도 보이지 않았다).
    static func draftMetadataBlob(_ metadata: DrawingLayoutMetadata, verse: Int) -> Data? {
        do {
            return try metadata.encodedBlob()
        } catch {
            Log.error("단일 Canvas — 초안의 좌표 정보를 인코딩하지 못했다. 잉크만 남기고, 이 초안은 「남은 필기」 에 표시 실패로 오른다",
                      "verse=\(verse)", "\(error)")
            return nil
        }
    }

    // MARK: - 세션

    /// 새 초안 세션 — 세션 번호를 올리고 기록을 비운다. 세션 ID 는 첫 초안을 쓸 때 정한다.
    func resetDraftSession(state: inout State) {
        state.drafts = DraftSessionState(epoch: state.drafts.epoch + 1)
        state.sessionValidity = Self.sessionValidity(session: state.editEnvironment, latest: state.editEnvironment)
    }

    /// 지금 초안 세션을 닫고 새로 연다 — 근거가 바뀌어 세션을 새로 열 때 부른다. `editEnvironment` 는 이미 새 환경이다.
    ///
    /// - 이 세션의 편집 문맥(현재 세대 · 장 전환으로 물러난 세대)을 닫은 세션으로 옮기고 **세대를 올린다.** 인계를 마친 뒤 늦게 온 그 세대의
    ///   편집은 새 세션이 아니라 닫은 세션의 초안(그 세션 ID · 근거 · 기준)이 되고 저장소에 쓰지 않는다(`finishLateEdit`). 캔버스는 같은
    ///   내용을 새 세대로 다시 받으며, 그때 남은 미보고 편집도 옛 세대로 보고한다.
    /// - 마지막으로 알던 내용(`loadedDrawings`)을 내려놓는다 — 다른 근거로 읽은 내용으로 새 세션을 합성하지 않는다. 다시 읽기에 실패하면
    ///   막고 「다시 시도」 를 띄운다(`blockingLoadFailure`).
    /// - 이 세션의 초안은 그 출처를 단 채 남고, 다음 조회에서 다른 세션의 초안으로 판정된다.
    func closeDraftSession(state: inout State, closing environment: DrawingEditEnvironment) {
        state.closedDrafts.sessions[state.drafts.epoch] = ClosedDraftSession(
            sessionID: state.drafts.sessionID,
            environment: environment,
            bases: state.drafts.loadedBases.merging(state.drafts.bases) { _, edited in edited },
            inherited: state.drafts.inherited
        )
        // 앞서 닫은 세션의 문맥도 캔버스가 그 세대를 지나기 전까지는 둔다 — 연달아 바뀐 뒤에 온 첫 세션의 늦은 보고도 그 세션의 초안이 된다.
        state.closedDrafts.contexts += [state.currentSession, state.retiredSession].compactMap { $0 }
        state.retiredSession = nil
        pruneClosedContexts(state: &state)
        if state.renderedData != nil {
            state.renderedRevision += 1
            // 합성된 장에 남아 있던 재조회 실패는 닫는 세션의 것이다 — 새 세션의 다시 읽기를 막는 실패로 되살리지 않는다.
            state.loadFailure = nil
        }
        state.loadedDrawings = nil
        resetDraftSession(state: &state)
    }

    /// 늦은 보고가 더 올 수 없는 닫은 문맥을 놓는다 — 붙은 모든 캔버스가 그보다 새 세대를 표시했고(그 전에 이전 세대의 마지막 획을 보고했다),
    /// 큐 · 코덱이 그 세대의 편집을 들고 있지 않다. 캔버스가 없으면 떨어질 때 마지막 보고를 마쳤다.
    func pruneClosedContexts(state: inout State) {
        let floor = state.attachedCanvases.values.min() ?? .max
        let queued = Set(state.editQueue.map(\.snapshot.generation))
        state.closedDrafts.contexts.removeAll { $0.generation < floor && !queued.contains($0.generation) }
        state.closedDrafts.prune()
    }

    /// 닫은 세션의 세대로 늦게 온 편집 — 그 세션의 문맥으로 계산했다. **그 세션의 마지막 초안**으로 남기고 저장소 · 새 세션에 섞지 않는다.
    func finishLateEdit(
        state: inout State,
        contextIndex index: Int,
        drawingData: Data,
        revision: Int,
        result: DrawingEditResult
    ) -> Effect<Action> {
        var context = state.closedDrafts.contexts[index]
        context.baselineData = drawingData
        context.ownership = result.ownership
        for (verse, rowID) in result.issuedRowIDs {
            context.activeRowIDs[verse] = rowID
        }
        state.closedDrafts.contexts[index] = context
        for mutation in result.mutations {
            let key = LateDraftKey(epoch: context.draftEpoch, rowID: mutation.rowID)
            if let existing = state.closedDrafts.pending[key], existing.revision > revision { continue }
            state.closedDrafts.pending[key] = PendingDrawingMutation(revision: revision, chapter: context.chapter, mutation: mutation)
        }
        Log.info("단일 Canvas — 닫은 세션의 세대로 늦게 온 편집을 그 세션의 초안으로 남긴다",
                 "generation=\(context.generation)", "count=\(result.mutations.count)")
        pruneClosedContexts(state: &state)
        return startDraftSaveIfPossible(state: &state, allowRetry: true)
    }

    // MARK: - 복구

    /// 그 환경의 계정 근거 묶음에 남은 이 장의 초안. **읽지 못하면 조회 실패(`.drafts`)다** — 빈 목록으로 두면 보이지 않는 초안 위에 같은
    /// 키 · 더 새 revision 의 초안을 써서 덮는다(초안 전용 세션에서는 그것이 유일한 사본이다). 조회 실패처럼 입력을 막고 다시 시도를 기다린다.
    static func loadDrafts(
        from store: (any VerseDraftStore)?,
        environment: DrawingEditEnvironment,
        chapter: BibleChapter
    ) async throws -> [VerseDraft] {
        guard let store else { return [] }
        // 확인 전 묶음의 초안은 **그때 참고하던 계정(힌트)이 지금 참고하는 계정과 같을 때만** 화면에 올린다(사용자 결정 2026-09-21,
        // 11차 리뷰 P1). 확인된 환경이든 확인 전 환경이든 같은 규칙이다 — 다른 힌트의 초안은 다른 계정의 필기일 수 있다. 파일은 남는다.
        // 복구 화면(④)도 **같은 함수로 같은 입력**(읽는 묶음을 모두 합침)을 만들어 판정한다 — 묶음마다 따로 판정하면 여기서 밀린 초안이
        // 목록에도 없다(2026-09-21 후속 리뷰 P0-2a).
        let drafts: [VerseDraft]
        do {
            drafts = try await VerseDraftRecoveryRule.screenDrafts(environment: environment) { scope in
                try await store.drafts(in: scope, chapter: chapter, translation: .NKRV)
            }.map(\.draft)
        } catch {
            Log.error("단일 Canvas — 이 장의 초안을 읽지 못했다. 입력을 막고 다시 시도를 기다린다", "\(error)")
            throw DrawingLoadFailure(message: "\(error)", source: .drafts)
        }
        // 초안을 읽은 삭제 세대가 이 조회의 환경과 다르다(그 사이 전체 삭제 · 읽지 못하던 세대를 다시 읽음). 그 환경으로 쓰는 새 초안은 거절되거나
        // 삭제 전 내용 위에 쓴 것이 된다 — 조회 실패처럼 막고 다시 읽는다.
        guard await store.currentGeneration() == environment.eraseGeneration else {
            Log.error("단일 Canvas — 초안을 읽은 삭제 세대가 조회 환경과 다르다. 다시 읽는다")
            throw DrawingLoadFailure(message: "erase generation changed", source: .drafts)
        }
        return drafts
    }

    /// 조회한 저장소 내용 위에 남은 초안을 겹친다 — 지금 세션의 초안과, 이어 보여도 되는 다른 세션의 초안(`VerseDraftRecoveryRule`).
    /// 이 장의 절 기준도 여기서 잡는다. 이미 편집한 절의 기준은 바꾸지 않는다(`drafts.bases`). **초안은 지우지 않는다** — 같은 내용이라
    /// 겹치지 않는 초안도 남긴다(ACC-1 F29).
    func recoverDrafts(state: inout State, snapshots: [VerseDrawingSnapshot], drafts: [VerseDraft]) -> [VerseDrawingSnapshot] {
        let chapter = state.chapter
        // 이 장에서 이 세션이 아직 편집하지 않은 절의 기준 · 이어 보인 초안은 이번 조회로 다시 정한다. 앞선 조회의 것이 남으면 이제 보이지 않는
        // 초안을 이어받아 지우거나 그 출처를 잇는다.
        let edited = Set(state.drafts.bases.keys)
        func isFresh(_ place: DraftVerse) -> Bool { place.chapter == chapter && !edited.contains(place) }
        state.drafts.loadedBases = state.drafts.loadedBases.filter { !isFresh($0.key) }
        state.drafts.adopted = state.drafts.adopted.filter { !isFresh($0.key) }
        state.drafts.inherited = state.drafts.inherited.filter { !isFresh($0.key) }

        // 대표 행 · 절 내용 · 행 내용 — 복구 화면(④)과 같은 자리에서 만든다.
        let view = VerseDraftStoreView(snapshots: snapshots)
        let representatives = view.representatives
        // 저장소 내용 그대로의 기준 — 아직 편집하지 않은 절이 편집을 시작하면 이것을 든다.
        for (verse, representative) in representatives {
            let fingerprint = view.verseContent[verse]
            state.drafts.loadedBases[DraftVerse(chapter: chapter, verse: verse)] = fingerprint.map {
                DraftBase(base: .legacy(rowID: representative.rowID, contentFingerprint: $0), fingerprint: $0)
            } ?? .empty
        }
        let plan = VerseDraftRecoveryRule.plan(
            drafts: drafts, storeContent: view.verseContent, environment: state.editEnvironment, sessionID: state.drafts.sessionID,
            storedRevisions: state.drafts.storedRevisions, storeRows: view.rows
        )
        // 절 메뉴가 「남은 필기 N」 을 띄울 근거 — 복구 화면(④)이 그 절에서 보일 것과 같은 수다.
        state.drafts.hiddenCounts = Dictionary(grouping: plan.kept, by: { $0.key.verse }).mapValues(\.count)
        state.drafts.hiddenKeys = Set(plan.kept.map(\.key))
        // 늦게 도착한 필사를 가릴 기준 — 이번에 읽은 저장소 내용 그대로(P0-3). 그 뒤 이 세션이 저장소에 쓴 것은 `finishSave` 가 겹친다.
        state.arrival.storeBaseline = snapshots
        var mutations: [VerseDrawingMutation] = []
        for draft in plan.shown {
            let verse = draft.key.verse
            let place = DraftVerse(chapter: chapter, verse: verse)
            let representative = representatives[verse]
            let rowID = representative?.rowID ?? draft.rowID
            var metadata: DrawingLayoutMetadata?
            if draft.lineData != nil {
                metadata = DrawingLayoutMetadata.decode(blob: draft.layoutMetadataData)
                guard metadata != nil else {
                    // 오지 않는 자리다 — 판정(`isDisplayable`)이 겹칠 수 없는 초안을 `kept` · `undisplayable` 로 이미 뺐다.
                    Log.error("단일 Canvas — 초안의 좌표 정보를 읽지 못해 겹치지 않는다(초안은 남김)", "verse=\(verse)")
                    continue
                }
            }
            if draft.key.sessionID != state.drafts.sessionID, isFresh(place) {
                // 다른 세션의 초안을 이어 보인다 — 기준은 그 초안의 것이다. 이 절을 편집하면 그 초안을 이어받는다. 보이기만 하는 초안이면 그 절의
                // 편집은 원 초안의 출처로 초안이 되고 저장소에 쓰지 않는다.
                state.drafts.adopted[place] = draft.ref
                state.drafts.loadedBases[place] = DraftBase(base: draft.base, fingerprint: draft.baseFingerprint)
                if plan.showOnly.contains(draft.key) { state.drafts.inherited[place] = draft.provenance }
            }
            guard let data = draft.lineData, let metadata else {
                mutations.append(.clear(verse: verse, rowID: rowID))
                continue
            }
            if representative == nil {
                state.drafts.draftOnlyRowIDs.insert(rowID)
                mutations.append(.create(verse: verse, rowID: rowID, data: data, metadata: metadata))
            } else {
                mutations.append(.replace(verse: verse, rowID: rowID, data: data, metadata: metadata))
            }
        }
        if !plan.kept.isEmpty || !plan.settled.isEmpty {
            Log.info("단일 Canvas — 보이지 않고 남긴 초안", "chapter=\(chapter.title.rawValue).\(chapter.chapter)",
                     "kept=\(plan.kept.count)", "uncertain=\(plan.uncertain.count)", "undisplayable=\(plan.undisplayable.count)",
                     "settled=\(plan.settled.count)")
        }
        return overlay(snapshots, with: mutations)
    }
}
