//
//  ChapterCanvasBackupFlushFeature.swift
//  CarveFeature
//
//  백업 전 flush 완료 신호 — 열린 필사 화면의 마지막 편집이 이 기기에 내구성 있게 남았는지 답한다
//  (설계 docs/backup-import-design.md §5-2 · 정책 §6-1 1단계). 저장 · 초안 · 인계 규칙은 그대로 두고 판정만 더한다.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 백업 전 flush 요청 하나와 그 답 (설계 §5-2).
///
/// `flushPending` 은 인계 요청과 저장 시작뿐이고 끝났다는 신호가 없다 — 보내기만 하고 백업을 시작하면 마지막 revision 이 초안 · 저장소에
/// 닿기 전의 상태를 읽는다. 그래서 요청을 들고 기다리다가 인계 완료 · 초안 저장 결과 · 저장 결과 · 캔버스 분리 뒤마다 판정해 **한 번만** 답한다.
///
/// | 인계 | 그때 상태 | 답 |
/// |---|---|---|
/// | 끝남 | 저장 실패 안내가 떠 있다(`saveRetryCount`) | `.failed(retryCount:)` |
/// | 끝남 | 지킬 편집이 없다(`hasUnsavedChanges == false`) | `.durable` |
/// | 끝나지 않음 · 저장 중 | 요청 뒤 5초(`backupFlushTimeout`) | `.timedOut` |
struct BackupFlushRequest: Equatable, Sendable {
    /// 내보내기가 보낸 요청 id — 답에 그대로 싣는다.
    let id: UUID
    /// 요청 때의 인계 토큰. 이 토큰 **이후**의 인계가 끝나면 요청 전까지의 편집은 모두 보고됐다 — 뷰는 가장 최근 요청에만 답하므로 세션 닫기 ·
    /// 도착 반영이 토큰을 더 올렸어도 `>=` 로 본다(`arrivalHandoffCompleted` 와 같다).
    let handoffToken: Int
    /// 인계가 끝났는가 — 끝나야 판정한다. 캔버스가 없거나 지킬 편집이 없으면 처음부터 끝난 것으로 둔다.
    var isHandedOff: Bool
    /// 보낸 답. nil 이면 아직 기다린다 — 답한 요청은 같은 id 가 다시 와도 다시 답하지 않는다.
    var outcome: CanvasFlushOutcome?

    /// 아직 답하지 않았다.
    var isWaiting: Bool { outcome == nil }
}

enum CanvasBackupFlushCancelID: Hashable {
    /// 그 요청의 시한. 요청마다 따로 두어, 앞 요청을 끝내는 취소가 새 요청의 시한을 건드리지 않는다.
    case timeout(UUID)
}

extension ChapterCanvasFeature {
    /// 백업 전 flush 를 기다리는 시한(설계 §5-2). 넘으면 `.timedOut` 이다 — 설정 쪽 시한(10초)보다 짧아 설정이 먼저 포기하지 않는다.
    static let backupFlushTimeout: Duration = .seconds(5)

    /// 백업 전 flush 의 액션들 — 요청과 시한.
    func reduceBackupFlush(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .backupFlushRequested(let id): backupFlushRequested(state: &state, id: id)
        case .backupFlushTimedOut(let id): backupFlushTimedOut(state: &state, id: id)
        default: .none
        }
    }

    /// 백업 전 flush 요청 — `flushPending` 과 같은 인계 · 저장을 시작하고, 마지막 편집이 이 기기에 남을 때까지 기다린다.
    ///
    /// - 닫는 중인 세션이면 `flushPending` 의 재시도 경로(`retrySessionEnd`)와 같다. 닫기가 인계를 다시 요청했으면 그 응답을 기다리고,
    ///   인계를 이미 마친 닫기(초안으로 남기는 중 · 실패)는 입력이 막힌 뒤라 더 보고될 획이 없다.
    /// - 캔버스가 없거나 지킬 편집이 없으면(`hasUnsavedChanges` — 긋는 중 · 디바운스 안의 미보고 획은 `isEditing` 이 잡는다) 인계를 기다리지 않고
    ///   곧바로 판정한다. 캔버스가 없어도 도는 초안 · 저장은 끝을 기다린다.
    /// - 마지막 요청과 같은 id 면 아무것도 하지 않는다. 다른 요청을 기다리던 중이면 그 요청은 `.timedOut` 으로 끝내고 새로 기다린다.
    /// - Returns: 인계 · 저장 effect 와, 곧바로 정해지면 그 답 · 아니면 시한.
    func backupFlushRequested(state: inout State, id: UUID) -> Effect<Action> {
        guard state.backupFlush?.id != id else { return .none }
        let superseded = finishBackupFlush(state: &state, outcome: .timedOut)
        let flush: Effect<Action>
        let awaitsHandoff: Bool
        if state.sessionEnd != nil {
            flush = retrySessionEnd(state: &state)
            if let phase = state.sessionEnd?.phase, case .handingOff = phase {
                awaitsHandoff = state.hasCanvas
            } else {
                awaitsHandoff = false
            }
        } else {
            // 비활성화와 같다 — 뷰에 인계를 요청해 디바운스 안의 마지막 획까지 보고받고, 실패했던 저장도 다시 한다.
            state.handoffToken += 1
            flush = startSaveIfPossible(state: &state, allowRetry: true)
            awaitsHandoff = state.hasCanvas
        }
        state.backupFlush = BackupFlushRequest(
            id: id, handoffToken: state.handoffToken, isHandedOff: !awaitsHandoff || !state.hasUnsavedChanges
        )
        let judged = judgeBackupFlush(state: &state)
        let timeout = state.backupFlush?.isWaiting == true ? waitForBackupFlush(id: id) : .none
        return .merge(superseded, flush, judged, timeout)
    }

    /// 기다리는 백업 전 flush 를 판정한다 — 인계가 끝났을 때만. 정해지면 답한다.
    ///
    /// 판정은 캔버스의 저장 상태 표시와 같은 값으로 한다 — 실패 안내가 떠 있으면(`saveRetryCount`) `.failed`, 지킬 편집이 없으면(`hasUnsavedChanges`)
    /// `.durable`. `.durable` 은 마지막 revision 까지 이 기기에 남았다는 뜻이다 — 저장소로 갈 것은 저장소에, 그 밖(소유 근거 없음 · 연결 보류 ·
    /// 보이기만 하는 절 · 닫는 세션)은 초안에. 새 조건을 만들지 않는다.
    /// - Note: 요청 · 인계 완료 · 초안 저장 결과 · 저장 결과 · 캔버스 분리 · 시한에서 부른다. 기다리는 요청이 없으면 아무것도 하지 않는다.
    func judgeBackupFlush(state: inout State) -> Effect<Action> {
        guard let request = state.backupFlush, request.isWaiting, request.isHandedOff else { return .none }
        if let retryCount = state.saveRetryCount {
            return finishBackupFlush(state: &state, outcome: .failed(retryCount: retryCount))
        }
        guard !state.hasUnsavedChanges else { return .none }
        return finishBackupFlush(state: &state, outcome: .durable)
    }

    /// 뷰가 인계를 마쳤다 — 요청이 올린 토큰 이후의 인계면 요청 전까지의 편집이 모두 보고됐다. 그리고 판정한다.
    func backupFlushHandoffCompleted(state: inout State, token: Int) -> Effect<Action> {
        if let request = state.backupFlush, request.isWaiting, token >= request.handoffToken {
            state.backupFlush?.isHandedOff = true
        }
        return judgeBackupFlush(state: &state)
    }

    /// 캔버스가 떨어졌다 — 떨어지며 미보고 편집 · 받아 둔 인계를 먼저 보고했으므로(`ChapterCanvasController.detach`) 마지막 캔버스였으면 인계가 끝났다.
    func backupFlushCanvasDetached(state: inout State) -> Effect<Action> {
        if !state.hasCanvas, state.backupFlush?.isWaiting == true {
            state.backupFlush?.isHandedOff = true
        }
        return judgeBackupFlush(state: &state)
    }

    /// 시한이 지났다 — 그 요청에 아직 답하지 않았으면 마지막으로 판정하고, 그래도 정해지지 않으면 `.timedOut`.
    ///
    /// 이미 답한 요청 · 다른 요청의 늦은 알림은 버린다. 마지막 판정은 판정 자리를 거치지 않고 정해진 경우(코덱이 바꿀 것 없이 끝난 보고처럼 초안 ·
    /// 저장 결과가 오지 않는 경로)를 시한 실패로 잘못 답하지 않으려는 것이다.
    func backupFlushTimedOut(state: inout State, id: UUID) -> Effect<Action> {
        guard let request = state.backupFlush, request.id == id, request.isWaiting else { return .none }
        let judged = judgeBackupFlush(state: &state)
        guard state.backupFlush?.isWaiting == true else { return judged }
        return finishBackupFlush(state: &state, outcome: .timedOut)
    }

    /// 기다리던 요청에 답한다 — 답을 적고, 시한을 거두고, 부모(코디네이터가 설정으로 중계)에 결과를 보낸다. 기다리는 요청이 없으면 아무것도 하지 않는다.
    private func finishBackupFlush(state: inout State, outcome: CanvasFlushOutcome) -> Effect<Action> {
        guard let request = state.backupFlush, request.isWaiting else { return .none }
        state.backupFlush?.outcome = outcome
        if outcome != .durable {
            Log.info("백업 전 flush — 마지막 편집이 이 기기에 남았는지 확인하지 못했다. 백업을 시작하지 않는다", "\(outcome)")
        }
        return .merge(
            .cancel(id: CanvasBackupFlushCancelID.timeout(request.id)),
            .send(.delegate(.backupFlushFinished(id: request.id, outcome: outcome)))
        )
    }

    /// 요청 뒤 시한을 잰다(`continuousClock` — 시험은 `TestClock`). 답하면 `finishBackupFlush` 가 거둔다.
    private func waitForBackupFlush(id: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.backupFlushTimeout)
            await send(.backupFlushTimedOut(id: id))
        }
        .cancellable(id: CanvasBackupFlushCancelID.timeout(id), cancelInFlight: true)
    }
}
