//
//  ChapterCanvasEditSession.swift
//  CarveFeature
//
//  편집 세션의 계정 · K 근거 — 바뀌면 미저장분을 그 세션의 초안으로 남기고 유효한 내용으로 다시 연다 (정책 §12-6 구현 순서 ① · ②).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 무효가 된 편집 세션을 닫는 중.
///
/// 편집 세션은 장을 불러온 뒤의 편집 전체다. 계정 근거 · K 는 **불러올 때** 정하고(`State.editEnvironment`), 그것이 바뀌면 세션을
/// 닫고 다시 불러오며 새로 정한다. 닫는 동안 입력을 막으므로, 환경이 바뀐 채로 새 편집이 시작되지 않는다 — 절마다 편집을 시작할 때
/// 근거를 고정하는 것과 같은 결과다(5차 리뷰 7).
struct EditSessionEnd: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// 뷰에 인계를 요청했다 — 뷰가 아직 보고하지 않은 편집(0.3초 디바운스 안의 획)을 보고하고 끝났다고 알리기를 기다린다.
        /// 시간을 재서 멎었다고 짐작하지 않는다(0.5초 대기는 완료 증명이 아니다). 뷰가 없으면 시한(`sessionHandoffTimeout`) 뒤에 넘어간다.
        case handingOff(token: Int)
        /// 인계를 마쳤다 — 코덱 큐에 남은 편집이 미저장분이 되기를 기다린다.
        case draining
        /// 남은 미저장분을 **닫는 세션의 초안**으로 남기는 중(② — ① 의 격리본을 대신한다).
        case preserving
        /// 초안으로 남기지 못했다(공간 부족 등). 입력 · 저장을 막은 채 「다시 시도」를 기다린다 — 미저장분을 버리지도, 바뀐 계정에 저장하지도 않는다.
        case failed(message: String)
    }

    /// 닫는 세션의 ID. 인계 시한 알림이 이 세션의 것인지 가린다.
    let id: String
    let reason: VerseEditContextValidity
    /// 무효가 된 세션의 환경. 남기는 초안은 **만들 당시의** 계정 범위 · K 를 든다.
    let environment: DrawingEditEnvironment
    /// 다시 불러올 때 쓸 최신 환경.
    var next: DrawingEditEnvironment
    var phase: Phase
}

enum CanvasEditSessionCancelID: Hashable {
    case environment
    case handoff
}

extension ChapterCanvasFeature {
    /// 뷰의 인계 응답을 기다리는 시한. 화면에 캔버스가 없으면 응답이 오지 않는다 — 그때는 받은 편집까지로 닫는다.
    /// 뷰는 획을 긋는 중이면 그 획이 반영된 뒤(0.3초)에 응답하므로 이보다 짧다.
    static let sessionHandoffTimeout: Duration = .seconds(1)

    /// 편집 환경의 변화를 구독한다. 장을 불러올 때마다 다시 건다.
    func observeEditEnvironment() -> Effect<Action> {
        .run { [editEnvironment] send in
            for await _ in editEnvironment.changes() {
                await send(.editEnvironmentChanged(await editEnvironment.current()))
            }
        }
        .cancellable(id: CanvasEditSessionCancelID.environment, cancelInFlight: true)
    }

    /// 세션의 근거가 최신 환경에서도 유효한가. 절 문맥과 같은 규칙(`VerseEditContextRule`)을 세션 전체에 적용한다.
    ///
    /// 불러온 데이터의 소유 근거는 **세션을 연 환경의 것**(`session.storeOwnership`)을 쓴다 — 근거는 불러온 내용에 대한 것이다.
    /// 지금은 근거를 줄 곳이 없어 모든 세션이 보존만 한다(ACC-1 에서 근거를 정한다).
    static func sessionValidity(session: DrawingEditEnvironment, latest: DrawingEditEnvironment) -> VerseEditContextValidity {
        let probe = VerseEditContext(
            contextID: "session", verse: 0, base: .empty, knownEpochs: session.knowledge?.all, account: session.accountBasis
        )
        return VerseEditContextRule.validity(
            of: probe, accountState: latest.accountState, deviceKnowledge: latest.knowledge, loadedDataOwner: session.storeOwnership
        )
    }

    /// 지킬 편집이 있는가 — 미저장분 · 도는 편집 · 그리는 중인 획.
    static func hasUnsavedWork(_ state: State) -> Bool {
        !state.isFullyPersisted || state.isEditing
    }

    func editEnvironmentChanged(state: inout State, latest: DrawingEditEnvironment) -> Effect<Action> {
        if var ending = state.sessionEnd {
            // 이미 닫는 중이다. 격리본의 근거(무효가 된 세션)는 그대로 두고, 다시 불러올 때 쓸 환경만 갱신한다.
            ending.next = latest
            state.sessionEnd = ending
            return .none
        }
        if state.editEnvironment == .unknown, !state.isComposed, !Self.hasUnsavedWork(state) {
            // 첫 환경 — 아직 불러온 내용도 편집도 없다. 이 환경으로 세션을 시작한다.
            state.editEnvironment = latest
            resetDraftSession(state: &state)
            return .none
        }
        let validity = Self.sessionValidity(session: state.editEnvironment, latest: latest)
        state.sessionValidity = validity
        switch validity {
        case .valid:
            // 같은 계정으로 다시 확인됐다(새 표). 확인을 기다리며 붙잡아 둔 미저장분을 이제 저장소에 쓴다.
            state.editEnvironment = latest
            let save = startSaveIfPossible(state: &state, allowRetry: true)
            guard state.reloadAfterAccountCheck else { return save }
            // 확인하는 동안 읽은 결과는 버렸다 — 이제 이 근거로 다시 읽는다.
            state.reloadAfterAccountCheck = false
            return .merge(save, reloadAfterSettling(state: &state))
        case .awaitingAccountConfirmation:
            // 계정이 바뀌었는지 아직 모른다 — 세션 근거는 그대로 두고, 편집은 초안에만 남기며 저장소 저장은 멈춘다.
            return .none
        case .preserveOnly:
            // 편집은 보존하되 귀속할 근거가 없다(확인 전에 시작 · K 를 읽지 못함 · 소유 근거 없음). 근거를 만들어 내지 않는다 — 마지막 확인
            // 계정은 근거가 아니다. 지킬 편집이 없고 최신 환경이 스스로 온전하면(확인된 계정 · 읽힌 K · 소유 근거) 그 환경으로 세션을 새로 연다.
            guard !Self.hasUnsavedWork(state), Self.sessionValidity(session: latest, latest: latest) == .valid else {
                // 초안이 마지막 보존이 됐다 — 확인을 기다리며 붙잡아 둔(이미 초안이 된) 미저장분을 내린다.
                dropDraftedPending(state: &state)
                return startSaveIfPossible(state: &state, allowRetry: true)
            }
            return restartSession(state: &state, with: latest)
        case .accountChanged, .eraseLearned:
            break
        }
        guard Self.hasUnsavedWork(state) else {
            // 지킬 미저장분이 없다. 새 환경으로 세션을 바꾸고 유효한 내용으로 다시 연다.
            return restartSession(state: &state, with: latest)
        }
        Log.info("편집 세션 — 계정 · 삭제 근거가 바뀌었다. 입력 · 저장을 막고 미저장분을 초안으로 남긴 뒤 다시 연다", "\(validity)")
        return beginSessionEnd(state: &state, reason: validity, next: latest)
    }

    /// 세션을 닫기 시작한다 — 입력 · 저장소 저장을 막고(`sessionEnd`), 뷰에 인계를 요청한다.
    func beginSessionEnd(state: inout State, reason: VerseEditContextValidity, next: DrawingEditEnvironment) -> Effect<Action> {
        state.handoffToken += 1
        let ending = EditSessionEnd(
            id: uuid().uuidString, reason: reason, environment: state.editEnvironment, next: next,
            phase: .handingOff(token: state.handoffToken)
        )
        state.sessionEnd = ending
        return .run { [clock, id = ending.id] send in
            try await clock.sleep(for: Self.sessionHandoffTimeout)
            await send(.sessionHandoffTimedOut(id: id))
        }
        .cancellable(id: CanvasEditSessionCancelID.handoff, cancelInFlight: true)
    }

    /// 새 환경으로 세션을 시작한다. 합성된 장이면 다시 읽고, 합성 전이면 도는 조회를 새 요청으로 바꿔 **옛 환경의 결과를 버린다**
    /// (요청 ID 가 바뀌므로 늦게 온 옛 결과는 `finishLoad` 가 버린다).
    func restartSession(state: inout State, with latest: DrawingEditEnvironment) -> Effect<Action> {
        state.editEnvironment = latest
        resetDraftSession(state: &state)
        state.reloadAfterAccountCheck = false
        if state.isComposed {
            return reloadAfterSettling(state: &state)
        }
        guard state.loadRequestID != nil, state.blockingLoadFailure == nil else { return .none }
        return requestLoad(state: &state)
    }

    /// 뷰가 인계를 마쳤다 — 이 세션의 편집은 모두 보고됐다. **지금 요청한 인계의 응답만** 받는다.
    func editHandoffCompleted(state: inout State, token: Int) -> Effect<Action> {
        guard var ending = state.sessionEnd, ending.phase == .handingOff(token: token) else { return .none }
        ending.phase = .draining
        state.sessionEnd = ending
        return .merge(.cancel(id: CanvasEditSessionCancelID.handoff), continueSessionEnd(state: &state))
    }

    /// 인계 응답이 시한 안에 오지 않았다(화면에 캔버스가 없음 등) — 받은 편집까지로 닫는다.
    /// **지금 닫는 세션의 시한만** 받는다 — 앞서 정리된 세션의 늦은 알림이 새로 닫는 세션을 서둘러 닫게 하지 않는다.
    func sessionHandoffTimedOut(state: inout State, id: String) -> Effect<Action> {
        guard var ending = state.sessionEnd, ending.id == id, case .handingOff = ending.phase else { return .none }
        Log.info("편집 세션 — 뷰의 인계 응답이 없다. 받은 편집까지로 닫는다")
        ending.phase = .draining
        state.sessionEnd = ending
        return continueSessionEnd(state: &state)
    }

    /// 인계를 마친 뒤 코덱이 편집을 마저 처리했을 수 있다 — 닫기를 잇는다.
    func resumeSessionEndIfDraining(state: inout State) -> Effect<Action> {
        guard state.sessionEnd?.phase == .draining else { return .none }
        return continueSessionEnd(state: &state)
    }

    /// 닫는 세션의 미저장분이 모두 그 세션의 초안이 됐으면 닫고, 아니면 초안을 남긴다.
    ///
    /// 초안은 이미 편집마다 남겼으므로 대개 곧바로 닫힌다. 남은 것은 초안을 쓰는 중이던 revision 과 인계로 받은 마지막 편집이다.
    func continueSessionEnd(state: inout State) -> Effect<Action> {
        guard var ending = state.sessionEnd else { return .none }
        switch ending.phase {
        case .handingOff, .failed:
            return .none
        case .draining, .preserving:
            break
        }
        dropDraftedPending(state: &state)
        guard state.editQueue.isEmpty, !state.isPreparingEdit, !state.isEditing else {
            // 인계로 받은 편집을 코덱이 아직 처리한다 — 끝나면(`mutationsPrepared`) 다시 잇는다.
            ending.phase = .draining
            state.sessionEnd = ending
            return .none
        }
        if state.pendingMutations.isEmpty, !state.isSavingDrafts {
            return finishSessionEnd(state: &state)
        }
        ending.phase = .preserving
        state.sessionEnd = ending
        return startDraftSaveIfPossible(state: &state, allowRetry: true)
    }

    /// 초안으로 남기지 못했다 — 입력 · 저장을 막은 채 「다시 시도」(`flushPending`)를 기다린다.
    func failSessionEnd(state: inout State, message: String) -> Effect<Action> {
        guard var ending = state.sessionEnd else { return .none }
        Log.error("편집 세션 — 미저장분을 초안으로 남기지 못했다. 입력 · 저장을 막은 채 다시 시도를 기다린다", message)
        ending.phase = .failed(message: message)
        state.sessionEnd = ending
        return .none
    }

    /// 닫는 세션의 미저장분을 모두 초안으로 남겼다 — 새 환경으로 세션을 바꾸고 유효한 내용으로 다시 연다.
    func finishSessionEnd(state: inout State) -> Effect<Action> {
        guard let ending = state.sessionEnd else { return .none }
        state.sessionEnd = nil
        state.editEnvironment = ending.next
        resetDraftSession(state: &state)
        state.reloadAfterAccountCheck = false
        if state.pendingMutations.isEmpty, case .failed = state.saveStatus {
            // 실패했던 저장의 내용은 초안으로 남겼다. 다시 시도할 것이 없으므로 실패로 남기지 않는다 — 남기면 재합성이 멈춘다.
            state.consecutiveSaveFailures = 0
            state.saveStatus = .idle
        }
        return reloadAfterSettling(state: &state)
    }

    /// 초안이 마지막 보존일 때(`draftsAreFinal`) — 그 revision 까지 초안이 된 미저장분을 큐에서 내리고 화면의 근거에 겹친다.
    func dropDraftedPending(state: inout State) {
        guard state.draftsAreFinal else { return }
        for (rowID, entry) in state.pendingMutations where (state.drafts.records[rowID]?.revision ?? 0) >= entry.revision {
            state.pendingMutations[rowID] = nil
            if case .create = entry.mutation { state.drafts.draftOnlyRowIDs.insert(rowID) }
            if entry.chapter == state.chapter, let loaded = state.loadedDrawings {
                state.loadedDrawings = overlay(loaded, with: [entry.mutation])
            }
        }
    }

    /// 초안으로 남기지 못한 세션을 다시 닫는다(「다시 시도」 · 백그라운드 진입). 입력은 닫기 시작할 때부터 막혀 있어 새 인계는 필요 없다.
    func retrySessionEnd(state: inout State) -> Effect<Action> {
        guard var ending = state.sessionEnd, case .failed = ending.phase else { return .none }
        ending.phase = .draining
        state.sessionEnd = ending
        return continueSessionEnd(state: &state)
    }

    /// 두 환경이 **같은 근거**인가 — 계정 상태 · K · 저장소 소유 근거. 확인 세대(표)는 보지 않는다: 같은 계정의 재확인은 근거를 바꾸지
    /// 않는다. 반대로 세대가 같거나 더 새롭다는 것도 근거가 같다는 뜻이 아니다 — 세대는 소유도 K 의 동등성도 나타내지 않는다(8차 리뷰).
    static func hasSameBasis(_ lhs: DrawingEditEnvironment, _ rhs: DrawingEditEnvironment) -> Bool {
        lhs.accountState == rhs.accountState && lhs.knowledge == rhs.knowledge && lhs.storeOwnership == rhs.storeOwnership
            && lhs.eraseGeneration == rhs.eraseGeneration
    }

    /// 조회 결과가 세션과 **다른 근거**로 읽혔다. **한 세션은 한 근거로 읽은 내용만 든다** — 다른 근거의 결과를 지금 세션에 섞지 않는다.
    ///
    /// - 지킬 편집이 없으면 결과의 근거로 새 세션을 연다. 결과는 그 근거로 읽은 것이므로 그대로 쓴다(nil 을 돌려 합성을 잇는다).
    /// - 지킬 편집이 있으면 결과를 버리고 지금 세션을 닫는다. 그 편집은 **지금 세션의 출처를 단 채** 보존하고(격리본 — ② 에서는 초안),
    ///   새 근거로 다시 읽는다.
    /// - Returns: 합성을 이어도 되면 nil, 아니면 결과를 버린 뒤의 효과.
    func resolveLoadBasisMismatch(state: inout State, loadedUnder environment: DrawingEditEnvironment) -> Effect<Action>? {
        if var ending = state.sessionEnd {
            // 이미 닫는 중이다 — 닫은 뒤 다시 읽는다. 결과는 버린다.
            ending.next = environment
            state.sessionEnd = ending
            return .none
        }
        let validity = Self.sessionValidity(session: state.editEnvironment, latest: environment)
        if validity == .awaitingAccountConfirmation, state.loadedDrawings != nil {
            // 계정을 확인하는 중에 읽은 결과다 — 어느 계정의 내용인지 아직 모른다. 섞지 않고 버리되 세션은 끝내지 않는다: 같은 계정으로
            // 확인되는 경우가 대부분이고, 닫으면 방금 쓴 초안이 다른 묶음(계정 미확인)으로 가려진다. 재합성이 기다리고 있으면 마지막으로 알던
            // 내용으로 합성해 입력을 열고(재조회 실패와 같은 출구), 확인이 끝나면 다시 읽는다.
            Log.info("편집 세션 — 계정 확인 중에 읽은 조회 결과를 버리고, 확인이 끝나면 다시 읽는다")
            state.reloadAfterAccountCheck = true
            if state.isReloading { recoverFromReloadFailure(state: &state) }
            return .none
        }
        guard Self.hasUnsavedWork(state), validity != .valid else {
            Log.info("편집 세션 — 조회 결과의 근거로 세션을 새로 연다", "\(validity)")
            let keepsWork = Self.hasUnsavedWork(state)
            state.editEnvironment = environment
            if keepsWork {
                // 유효한 채로 근거만 달라졌다 — 지킬 편집을 이 세션에 둔 채 이어 간다.
                state.sessionValidity = validity
            } else {
                resetDraftSession(state: &state)
            }
            return nil
        }
        Log.info("편집 세션 — 다른 근거로 읽은 조회 결과를 버리고, 지금 세션의 편집을 초안으로 남긴 뒤 다시 연다", "\(validity)")
        return beginSessionEnd(state: &state, reason: validity, next: environment)
    }
}
