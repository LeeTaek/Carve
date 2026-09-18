//
//  ChapterCanvasEditSession.swift
//  CarveFeature
//
//  편집 세션의 계정 · K 근거 — 바뀌면 미저장분을 격리하고 유효한 내용으로 다시 연다 (정책 §12-6 구현 순서 ①).
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
        /// 편집이 멎기를 기다린다 — 코덱 큐와 뷰의 늦은 보고(0.3초 뒤)까지 받아 격리에 넣기 위해서다.
        case settling
        /// 격리본을 저장하는 중. 격리에 넣은 미저장분(행 ID → revision)을 기억한다.
        case quarantining(captured: [BibleDrawingRowID: Int])
        /// 격리하지 못했다(공간 부족 등). 입력 · 저장을 막은 채 「다시 시도」를 기다린다 — 미저장분을 버리지도, 바뀐 계정에 저장하지도 않는다.
        case failed(message: String)
    }

    /// 닫는 세션의 ID. 격리본 ID 에 들어가 재시도해도 같은 격리본이 된다.
    let id: String
    let reason: VerseEditContextValidity
    /// 무효가 된 세션의 환경. 격리본은 **만들 당시의** 계정 범위 · K 를 든다.
    let environment: DrawingEditEnvironment
    /// 다시 불러올 때 쓸 최신 환경.
    var next: DrawingEditEnvironment
    var phase: Phase
}

enum CanvasEditSessionCancelID: Hashable {
    case environment
    case settle
}

extension ChapterCanvasFeature {
    /// 편집이 멎었다고 볼 때까지 기다리는 시간. 뷰는 획이 바뀐 뒤 0.3초에 편집을 보고한다(`ChapterCanvasController`).
    static let sessionSettleDelay: Duration = .milliseconds(500)

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
    /// 불러온 데이터의 소유 근거(`loadedDataOwner`)는 아직 줄 곳이 없다 — 확인 전에 시작한 세션은 보존만 한다(ACC-1 에서 근거를 정한다).
    static func sessionValidity(session: DrawingEditEnvironment, latest: DrawingEditEnvironment) -> VerseEditContextValidity {
        let probe = VerseEditContext(
            contextID: "session", verse: 0, base: .empty, knownEpochs: session.knowledge?.all, account: session.accountBasis
        )
        return VerseEditContextRule.validity(of: probe, accountState: latest.accountState, deviceKnowledge: latest.knowledge)
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
            return .none
        }
        let validity = Self.sessionValidity(session: state.editEnvironment, latest: latest)
        switch validity {
        case .valid:
            // 같은 계정으로 다시 확인됐다(새 표).
            state.editEnvironment = latest
            return .none
        case .awaitingAccountConfirmation:
            // 계정이 바뀌었는지 아직 모른다 — 세션 근거는 그대로 둔다.
            return .none
        case .preserveOnly:
            // 편집은 보존하되 귀속할 근거가 없다(확인 전에 시작 · K 를 읽지 못함). 근거를 만들어 내지 않는다 — 마지막 확인 계정은 근거가
            // 아니다. 지킬 편집이 없고 최신 환경이 스스로 온전하면(확인된 계정 · 읽힌 K) 그 환경으로 세션을 새로 연다.
            guard !Self.hasUnsavedWork(state), Self.sessionValidity(session: latest, latest: latest) == .valid else { return .none }
            return restartSession(state: &state, with: latest)
        case .accountChanged, .eraseLearned:
            break
        }
        guard Self.hasUnsavedWork(state) else {
            // 지킬 미저장분이 없다. 새 환경으로 세션을 바꾸고 유효한 내용으로 다시 연다.
            return restartSession(state: &state, with: latest)
        }
        Log.info("편집 세션 — 계정 · 삭제 근거가 바뀌었다. 입력 · 저장을 막고 미저장분을 격리한 뒤 다시 연다", "\(validity)")
        state.sessionEnd = EditSessionEnd(
            id: uuid().uuidString, reason: validity, environment: state.editEnvironment, next: latest, phase: .settling
        )
        return scheduleSessionSettle()
    }

    /// 새 환경으로 세션을 시작한다. 합성된 장이면 다시 읽고, 합성 전이면 도는 조회를 새 요청으로 바꿔 **옛 환경의 결과를 버린다**
    /// (요청 ID 가 바뀌므로 늦게 온 옛 결과는 `finishLoad` 가 버린다).
    func restartSession(state: inout State, with latest: DrawingEditEnvironment) -> Effect<Action> {
        state.editEnvironment = latest
        if state.isComposed {
            return reloadAfterSettling(state: &state)
        }
        guard state.loadRequestID != nil, state.blockingLoadFailure == nil else { return .none }
        return requestLoad(state: &state)
    }

    func scheduleSessionSettle() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.sessionSettleDelay)
            await send(.sessionEndSettled)
        }
        .cancellable(id: CanvasEditSessionCancelID.settle, cancelInFlight: true)
    }

    /// 편집이 멎었으면 미저장분을 격리한다. 아직 흐르고 있으면 한 번 더 기다린다.
    func sessionEndSettled(state: inout State) -> Effect<Action> {
        guard var ending = state.sessionEnd, ending.phase == .settling else { return .none }
        guard state.editQueue.isEmpty, !state.isPreparingEdit, !state.isEditing else {
            return scheduleSessionSettle()
        }
        let pending = state.pendingMutations
        guard !pending.isEmpty else { return finishSessionEnd(state: &state) }
        ending.phase = .quarantining(captured: pending.mapValues(\.revision))
        state.sessionEnd = ending
        let items = pending.values
            .sorted { ($0.chapter.title.rawValue, $0.chapter.chapter, $0.mutation.verse) < ($1.chapter.title.rawValue, $1.chapter.chapter, $1.mutation.verse) }
            .map(Self.quarantineItem)
        let environment = ending.environment
        let batchID = ending.id
        return .run { [quarantine] send in
            do {
                try await quarantine.quarantine(items, environment: environment, batchID: batchID)
                await send(.sessionQuarantineFinished(failure: nil))
            } catch {
                await send(.sessionQuarantineFinished(failure: "\(error)"))
            }
        }
    }

    func sessionQuarantineFinished(state: inout State, failure: String?) -> Effect<Action> {
        guard var ending = state.sessionEnd, case .quarantining(let captured) = ending.phase else { return .none }
        if let failure {
            Log.error("편집 세션 — 미저장분을 격리하지 못했다. 입력 · 저장을 막은 채 다시 시도를 기다린다", failure)
            ending.phase = .failed(message: failure)
            state.sessionEnd = ending
            return .none
        }
        // 격리한 것만 내려놓는다. 그 사이 늦게 들어온 편집도 같은 세션의 것이므로 한 번 더 격리한다.
        for (key, revision) in captured where state.pendingMutations[key]?.revision == revision {
            state.pendingMutations[key] = nil
        }
        guard state.pendingMutations.isEmpty, state.editQueue.isEmpty, !state.isPreparingEdit else {
            ending.phase = .settling
            state.sessionEnd = ending
            return scheduleSessionSettle()
        }
        return finishSessionEnd(state: &state)
    }

    /// 격리가 끝났다 — 새 환경으로 세션을 바꾸고 유효한 내용으로 다시 연다.
    func finishSessionEnd(state: inout State) -> Effect<Action> {
        guard let ending = state.sessionEnd else { return .none }
        state.sessionEnd = nil
        state.editEnvironment = ending.next
        if state.pendingMutations.isEmpty, case .failed = state.saveStatus {
            // 실패했던 저장의 내용은 격리했다. 다시 시도할 것이 없으므로 실패로 남기지 않는다 — 남기면 재합성이 멈춘다.
            state.consecutiveSaveFailures = 0
            state.saveStatus = .idle
        }
        return reloadAfterSettling(state: &state)
    }

    /// 격리하지 못한 세션을 다시 닫는다(「다시 시도」 · 백그라운드 진입).
    func retrySessionEnd(state: inout State) -> Effect<Action> {
        guard var ending = state.sessionEnd, case .failed = ending.phase else { return .none }
        ending.phase = .settling
        state.sessionEnd = ending
        return scheduleSessionSettle()
    }

    static func quarantineItem(_ pending: PendingDrawingMutation) -> DrawingQuarantineItem {
        switch pending.mutation {
        case .create(let verse, _, let data, let metadata), .replace(let verse, _, let data, let metadata):
            DrawingQuarantineItem(
                chapter: pending.chapter, verse: verse, revision: pending.revision, lineData: data, drawingVersion: 3,
                layoutMetadataData: try? metadata.encodedBlob()
            )
        case .clear(let verse, _):
            DrawingQuarantineItem(
                chapter: pending.chapter, verse: verse, revision: pending.revision, lineData: nil, drawingVersion: nil, layoutMetadataData: nil
            )
        }
    }
}
