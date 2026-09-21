//
//  ChapterCanvasArrivalFeature.swift
//  CarveFeature
//
//  늦게 도착한 필사를 열린 장에 반영한다 (2026-09-21 후속 리뷰 P0-3 — 2.0.0 필수 범위, 사용자 결정).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 늦게 도착한 필사(재설치 뒤 초기 import 등)를 **열린 장**에 반영하는 상태 — 2.0.0 필수 범위(사용자 결정 2026-09-21).
///
/// | 지금 이 장 | 도착한 뒤 |
/// |---|---|
/// | 이 세션이 편집하지 않았고 초안도 겹쳐 보이지 않는다 | 저장소를 다시 읽어 **자동으로 반영**한다 |
/// | 이 세션이 편집했다(펜을 뗀 뒤 포함) · 앞선 초안이 겹쳐 보인다 | 바꾸지 않고 「다른 필사가 도착했어요 · 확인하기」 |
/// | 획을 긋는 중 · 미보고 획 · 코덱 · 초안 · 저장소 저장 중 | 보류한다 — 지금 필기를 먼저 보존한 뒤 이어 간다 |
/// | 다시 읽지 못함 | 지금 화면 · 초안을 그대로 두고 「다시 시도」 |
///
/// - **펜을 대고 있는지만 보지 않는다.** 이미 편집하고 펜을 뗀 장도 자동으로 바꾸지 않는다 — 그 장의 절 기준(`drafts.bases`)이 편집한 흔적이다.
/// - 도착 신호(`CloudImportArrivalClient`)는 어느 장이 바뀌었는지 모른다. 조용해지면 뷰에서 미보고 획까지 인계받고 **저장소만 다시 읽어** 이
///   장이 실제로 바뀌었는지 먼저 본다 — 바뀌지 않았으면 아무것도 하지 않는다. 이 세션이 저장소에 쓴 행은 비교에서 뺀다.
/// - **「확인하기」 는 앱을 다시 연 것과 같다.** 지금 필기를 보존한 뒤(인계 · 초안 · 저장이 끝나기를 기다림) 저장소와 초안을 다시 읽고, **읽은
///   뒤에야** 이 세션을 닫아 그 초안들을 다른 세션의 초안으로 다시 판정한다(`VerseDraftRecoveryRule`). 기준이 달라진 초안은 조용히 숨기지 않고
///   「남은 필기」 로 잇는다. 다시 읽지 못하면 세션도 화면도 그대로다. 자동 병합 · 새 복구 기능은 없다.
struct ArrivalState: Equatable, Sendable {
    enum Intent: Equatable, Sendable {
        /// 도착했다 — 이 장이 바뀌었는지 보고, 편집하지 않은 장이면 자동으로 반영한다.
        case check
        /// 사용자가 「확인하기」 를 눌렀다 — 지금 필기를 보존한 뒤 새 세션으로 다시 읽는다.
        case confirm
    }

    enum Phase: Equatable, Sendable {
        case idle
        /// 조용해지기를 기다린다(획 · 미보고 획 · 코덱 · 초안 · 저장소 저장 · 다시 읽기 · 지우기 · 세션 닫기).
        case waiting(Intent)
        /// 뷰에 인계를 요청했다 — 미보고 획까지 받은 뒤 이어 간다.
        case handingOff(Intent, token: Int)
        /// 저장소만 다시 읽어 이 장이 바뀌었는지 본다.
        case checking(requestID: UUID)
        /// 다시 읽는 중 — 이 요청의 결과가 오면 마무리한다. 재조회가 미뤄져 새 요청이 나가면 그 요청을 따라간다(`requestLoad`).
        case reloading(Intent, requestID: UUID)
    }

    /// 마지막 조회를 시작한 시각 — 그보다 앞서 끝난 import 는 그 조회에 이미 들어 있다.
    var loadStartedAt: Date?
    var phase: Phase = .idle
    /// 확인 · 반영하는 사이에 또 도착했다 — 끝난 뒤 한 번 더 본다.
    var arrivedAgain = false
    /// 사용자에게 보이는 안내.
    var notice: ArrivalNotice?
    /// 마지막으로 합성한 저장소 내용(행마다) — 도착 확인 조회와 견준다.
    var baseline: [BibleDrawingRowID: VerseDraftStoreRow]?
    /// 「확인하기」 직전 이 장에 보이던 초안 — 다시 읽은 뒤 자동으로 표시되지 않게 된 것을 센다.
    var displayedDrafts: Set<VerseDraftKey> = []
}

/// 도착 안내 — 사라지지 않고 할 일이 끝날 때까지 남는다(「남은 필기」 안내만 닫을 수 있다).
enum ArrivalNotice: Equatable, Sendable {
    /// 편집한 장에 다른 필사가 도착했다 — 「확인하기」.
    case arrived
    /// 「확인하기」 를 눌렀다 — 지금 필기를 보존하고 다시 읽는 중.
    case confirming
    /// 도착한 필사를 다시 읽지 못했다 — 지금 화면 · 초안은 그대로다. 「다시 시도」 는 같은 일을 다시 한다.
    case reloadFailed(ArrivalState.Intent)
    /// 다시 읽었더니 이 기기의 초안 N개가 자동으로 표시되지 않는다 — 「남은 필기 보기」.
    case draftsHidden(count: Int)

    var message: String {
        switch self {
        case .arrived: "다른 필사가 도착했어요"
        case .confirming: "지금 필기를 보존하고 도착한 필사를 읽는 중이에요"
        case .reloadFailed: "도착한 필사를 불러오지 못했어요. 지금 화면과 필기는 그대로예요"
        case .draftsHidden(let count): "이 기기에서 쓴 필기 \(count)개는 도착한 필사와 기준이 달라 자동으로 표시하지 않아요"
        }
    }

    /// 버튼 제목. 없으면 버튼을 두지 않는다.
    var actionTitle: String? {
        switch self {
        case .arrived: "확인하기"
        case .confirming: nil
        case .reloadFailed: "다시 시도"
        case .draftsHidden: "남은 필기 보기"
        }
    }
}

enum CanvasArrivalCancelID: Hashable {
    case arrivals
}

extension ChapterCanvasFeature.State {
    /// 이 장이 **저장소 내용 그대로**인가 — 이 세션이 편집하지 않았고(펜을 뗀 뒤도 편집이다) 앞선 세션의 초안도 겹쳐 보이지 않는다.
    /// 그래야 도착한 필사로 자동 갱신한다 — 겹쳐 보이던 초안을 조용히 감추지 않는다.
    var showsOnlyStore: Bool {
        let chapter = chapter
        return !drafts.bases.keys.contains { $0.chapter == chapter }
            && !pendingMutations.values.contains { $0.chapter == chapter }
            && !drafts.adopted.keys.contains { $0.chapter == chapter }
            && !drafts.inherited.keys.contains { $0.chapter == chapter }
    }

    /// 이 장에 지금 보이는 초안 — 이 세션이 쓴 것과 이어 보인 앞선 세션의 것.
    var displayedDraftKeys: Set<VerseDraftKey> {
        let chapter = chapter
        let own = drafts.records.values.map(\.key).filter { $0.title == chapter.title.rawValue && $0.chapter == chapter.chapter }
        let adopted = drafts.adopted.filter { $0.key.chapter == chapter }.map(\.value.key)
        return Set(own).union(adopted)
    }

    /// 도착을 다뤄도 될 만큼 조용한가 — 합성돼 있고, 세션을 닫거나 다시 읽거나 지우는 중이 아니며, 획 · 코덱 · 초안 · 저장소 저장이 멎었다
    /// (`isSettledForReload` 는 획을 긋는 중 · 미보고 획도 본다). 「확인하기」 는 이 세션을 닫으므로 미저장분이 **하나도** 없어야 한다.
    func isQuietForArrival(_ intent: ArrivalState.Intent) -> Bool {
        let quiet = isComposed && sessionEnd == nil && blockingLoadFailure == nil && !isReloading && !reloadWhenSettled && !isErasing
            && isSettledForReload
        switch intent {
        case .check: return quiet
        case .confirm: return quiet && isFullyPersisted
        }
    }
}

extension ChapterCanvasFeature {
    /// 도착 반영의 액션들.
    func reduceArrival(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .importArrived(let date): importArrived(state: &state, at: date)
        case let .arrivalChecked(requestID, result): arrivalChecked(state: &state, requestID: requestID, result: result)
        case .arrivalNoticeTapped: arrivalNoticeTapped(state: &state)
        case .arrivalNoticeDismissed: arrivalNoticeDismissed(state: &state)
        default: .none
        }
    }

    /// import 성공 신호를 구독한다. 장을 불러올 때마다 다시 건다.
    func observeArrivals() -> Effect<Action> {
        .run { [arrivals] send in
            for await date in arrivals.arrivals() {
                await send(.importArrived(at: date))
            }
        }
        .cancellable(id: CanvasArrivalCancelID.arrivals, cancelInFlight: true)
    }

    /// iCloud 에서 받은 필사가 저장소에 들어왔을 수 있다.
    func importArrived(state: inout State, at date: Date) -> Effect<Action> {
        // 조회를 시작하기 전에 끝난 import 는 그 조회에 이미 들어 있다.
        if let started = state.arrival.loadStartedAt, date <= started { return .none }
        switch state.arrival.phase {
        case .idle:
            state.arrival.phase = .waiting(.check)
        case .checking, .reloading:
            // 이미 읽고 있는 결과가 이 도착을 담았는지 모른다 — 끝난 뒤 한 번 더 본다.
            state.arrival.arrivedAgain = true
        case .waiting, .handingOff:
            // 아직 읽기 전이다 — 그때 읽는 저장소에 이 도착도 들어 있다.
            break
        }
        return continueArrival(state: &state)
    }

    /// 도착 반영을 잇는다 — 모든 액션 뒤에 부른다. 조용해졌으면 뷰에 인계를 요청하고(미보고 획까지 받는다), 캔버스가 없으면 곧바로 잇는다.
    func continueArrival(state: inout State) -> Effect<Action> {
        guard case .waiting(let intent) = state.arrival.phase, state.isQuietForArrival(intent) else { return .none }
        guard state.hasCanvas else { return proceedArrival(state: &state, intent: intent) }
        state.handoffToken += 1
        state.arrival.phase = .handingOff(intent, token: state.handoffToken)
        return .none
    }

    /// 뷰가 인계를 마쳤다. 도착이 요청한 토큰 **이후**의 인계면 그 앞의 획은 모두 보고됐다 — 비활성화 · 세션 닫기가 토큰을 더 올렸어도 잇는다.
    func arrivalHandoffCompleted(state: inout State, token: Int) -> Effect<Action> {
        guard case .handingOff(let intent, let requested) = state.arrival.phase, token >= requested else { return .none }
        return proceedArrival(state: &state, intent: intent)
    }

    /// 캔버스가 떨어졌다 — 인계를 기다리던 도착은 떨어지며 보고를 마쳤으니 잇는다.
    func arrivalCanvasDetached(state: inout State) -> Effect<Action> {
        guard !state.hasCanvas, case .handingOff(let intent, _) = state.arrival.phase else { return .none }
        return proceedArrival(state: &state, intent: intent)
    }

    /// 인계를 마쳤다(또는 캔버스가 없다) — 여전히 조용하면 확인 조회나 다시 읽기를 시작한다. 인계로 받은 획이 아직 처리 중이면 기다린다.
    private func proceedArrival(state: inout State, intent: ArrivalState.Intent) -> Effect<Action> {
        guard state.isQuietForArrival(intent) else {
            state.arrival.phase = .waiting(intent)
            return .none
        }
        switch intent {
        case .check:
            let requestID = uuid()
            state.arrival.phase = .checking(requestID: requestID)
            let chapter = state.chapter
            return .run { [repository] send in
                do {
                    await send(.arrivalChecked(requestID: requestID, .success(try await repository.load(chapter: chapter))))
                } catch {
                    await send(.arrivalChecked(requestID: requestID, .failure(DrawingLoadFailure(message: "\(error)"))))
                }
            }
        case .confirm:
            return startArrivalReload(state: &state, intent: .confirm)
        }
    }

    /// 확인 조회의 결과 — 이 장이 바뀌었으면 편집하지 않은 장은 자동으로 다시 읽고, 편집한 장은 알린다.
    func arrivalChecked(state: inout State, requestID: UUID, result: Result<DrawingChapterLoad, DrawingLoadFailure>) -> Effect<Action> {
        guard case .checking(let current) = state.arrival.phase, current == requestID else { return .none }
        state.arrival.phase = .idle
        switch result {
        case .failure(let failure):
            // 확인하지 못했다 — 화면 · 초안은 그대로 두고 알린다. 「다시 시도」 는 확인부터 다시 한다.
            Log.error("도착 반영 — 이 장이 바뀌었는지 확인하지 못했다. 화면은 그대로 둔다", failure.message)
            state.arrival.notice = .reloadFailed(.check)
            rearmIfArrivedAgain(state: &state)
            return .none
        case .success(let loaded):
            let own = Set(state.drafts.storedRevisions.keys).union(state.inFlightBatch.keys)
            let changed = loaded.generation != state.storeGeneration
                || Self.storeChanged(VerseDraftStoreView(snapshots: loaded.snapshots).rows, since: state.arrival.baseline, excluding: own)
            guard changed else {
                // 이 장은 그대로다 — 다른 장의 필사가 도착했다. 아무것도 하지 않는다.
                rearmIfArrivedAgain(state: &state)
                return .none
            }
            // 바뀌었다 — 이제부터 읽는 것(자동 반영 · 확인하기)은 사이에 또 온 도착까지 담는다.
            state.arrival.arrivedAgain = false
            guard state.isQuietForArrival(.check) else {
                // 확인하는 사이 편집이 시작됐다 — 멎은 뒤 다시 본다.
                state.arrival.phase = .waiting(.check)
                return .none
            }
            guard state.showsOnlyStore else {
                // 편집했거나 초안이 겹쳐 보이는 장 — 자동으로 바꾸지 않는다(사용자 결정).
                Log.info("도착 반영 — 편집한 장에 다른 필사가 도착했다. 바꾸지 않고 알린다", "\(state.chapter.title.rawValue).\(state.chapter.chapter)")
                if state.arrival.notice != .confirming { state.arrival.notice = .arrived }
                return .none
            }
            Log.info("도착 반영 — 편집하지 않은 장에 다른 필사가 도착했다. 다시 읽어 반영한다")
            return startArrivalReload(state: &state, intent: .check)
        }
    }

    /// 도착 안내의 버튼.
    func arrivalNoticeTapped(state: inout State) -> Effect<Action> {
        switch state.arrival.notice {
        case .arrived, .reloadFailed(.confirm):
            // 도는 확인 조회 · 인계는 이것으로 대신한다 — 확인하기도 최신 저장소를 읽는다. 다시 읽는 중이면 그 결과를 기다린다.
            if case .reloading = state.arrival.phase { return .none }
            state.arrival.notice = .confirming
            state.arrival.phase = .waiting(.confirm)
            return continueArrival(state: &state)
        case .reloadFailed(.check):
            // 다시 확인한다. 다른 도착으로 이미 확인이 돌고 있으면 그 결과에 맡긴다 — 버튼이 아무 일도 하지 않는 것처럼 두지 않는다.
            state.arrival.notice = nil
            if state.arrival.phase == .idle { state.arrival.phase = .waiting(.check) }
            return continueArrival(state: &state)
        case .draftsHidden:
            // 자동으로 표시되지 않게 된 초안을 보는 자리 — 설정 → 「남은 필기」(읽기 전용).
            state.arrival.notice = nil
            return .send(.delegate(.draftRecoveryRequested))
        case .confirming, nil:
            return .none
        }
    }

    /// 도착 안내를 닫는다 — 「남은 필기」 안내만 닫을 수 있다. 할 일이 남은 안내(확인하기 · 다시 시도)는 남긴다.
    func arrivalNoticeDismissed(state: inout State) -> Effect<Action> {
        if case .draftsHidden = state.arrival.notice { state.arrival.notice = nil }
        return .none
    }

    /// 도착한 필사로 다시 읽는다. 입력은 다시 읽는 동안 닫힌다(`isReloading`).
    private func startArrivalReload(state: inout State, intent: ArrivalState.Intent) -> Effect<Action> {
        if intent == .confirm {
            // 「확인하기」 직전 이 장에 보이던 초안 — 다시 읽은 뒤 자동으로 표시되지 않게 된 것을 「남은 필기」 로 잇는다.
            state.arrival.displayedDrafts = state.displayedDraftKeys
        }
        let effect = startReload(state: &state)
        state.arrival.phase = .reloading(intent, requestID: state.loadRequestID ?? uuid())
        return effect
    }

    /// 다시 읽기가 미뤄져 새 조회가 나갔다 — 도착 반영은 그 조회를 따라간다.
    func followArrivalReload(state: inout State, requestID: UUID) {
        guard case .reloading(let intent, _) = state.arrival.phase else { return }
        state.arrival.phase = .reloading(intent, requestID: requestID)
    }

    /// 「확인하기」 의 다시 읽기가 **성공했고 지금 합성할 수 있을 때만** 이 세션을 닫는다 — 읽은 초안(이 세션의 것 포함)을 다른 세션의 초안으로 다시
    /// 판정하게 한다. 읽지 못했거나 아직 합성하지 못하면 닫지 않는다(세션도 화면도 그대로).
    func closeSessionForArrival(state: inout State, requestID: UUID) {
        guard case .reloading(.confirm, let current) = state.arrival.phase, current == requestID, state.isSettledForReload else { return }
        Log.info("도착 반영 — 확인하기: 지금 필기를 보존했다. 이 세션을 닫고 새로 읽은 내용으로 다시 연다")
        closeDraftSession(state: &state, closing: state.editEnvironment)
    }

    /// 다시 읽기를 마쳤다 — 합성했거나(성공) 지금 화면을 그대로 두었다(실패).
    func finishArrivalReload(state: inout State, requestID: UUID, succeeded: Bool) {
        if succeeded, state.arrival.notice == .reloadFailed(.check) {
            // 다른 경로의 다시 읽기가 최신 저장소로 합성했다 — 확인 실패 안내는 더 말할 것이 없다.
            state.arrival.notice = nil
        }
        guard case .reloading(let intent, let current) = state.arrival.phase, current == requestID else { return }
        state.arrival.phase = .idle
        guard succeeded else {
            Log.error("도착 반영 — 다시 읽지 못했다. 지금 화면 · 초안을 그대로 두고 다시 시도를 둔다", "\(intent)")
            state.arrival.notice = .reloadFailed(intent)
            state.arrival.displayedDrafts = []
            rearmIfArrivedAgain(state: &state)
            return
        }
        switch intent {
        case .check:
            // 자동 반영을 마쳤다. 앞서 확인하기가 남긴 「남은 필기」 안내는 그대로 둔다.
            if state.arrival.notice == .reloadFailed(.check) { state.arrival.notice = nil }
        case .confirm:
            // 기준이 달라져 자동으로 표시되지 않게 된 내 초안 — 조용히 숨기지 않고 「남은 필기」 로 잇는다.
            let hidden = state.arrival.displayedDrafts.intersection(state.drafts.hiddenKeys).count
            state.arrival.notice = hidden > 0 ? .draftsHidden(count: hidden) : nil
        }
        state.arrival.displayedDrafts = []
        rearmIfArrivedAgain(state: &state)
    }

    /// 확인 · 반영하는 사이에 또 도착했으면 한 번 더 본다 — 다음 액션 뒤(`continueArrival`)에 이어 간다.
    private func rearmIfArrivedAgain(state: inout State) {
        guard state.arrival.arrivedAgain, state.arrival.phase == .idle else { return }
        state.arrival.arrivedAgain = false
        state.arrival.phase = .waiting(.check)
    }

    /// 이 장의 저장소 내용이 마지막으로 합성한 뒤 바뀌었는가 — 이 세션이 저장소에 쓴 행은 빼고 견준다. 기준이 없으면 바뀐 것으로 본다.
    static func storeChanged(
        _ fresh: [BibleDrawingRowID: VerseDraftStoreRow],
        since baseline: [BibleDrawingRowID: VerseDraftStoreRow]?,
        excluding own: Set<BibleDrawingRowID>
    ) -> Bool {
        guard let baseline else { return true }
        return fresh.filter { !own.contains($0.key) } != baseline.filter { !own.contains($0.key) }
    }
}

