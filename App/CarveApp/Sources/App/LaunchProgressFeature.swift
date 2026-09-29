//
//  LaunchProgressFeature.swift
//  CarveApp
//
//  Created by 이택성 on 7/21/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import Domain
import CarveToolkit

import ComposableArchitecture

/// 시작 화면 — 로컬 저장소를 준비하고, **초기 복원일 때만** iCloud 의 필사를 기다린다 (정책 §3 · §3-1, 2026-09-21 후속 리뷰 P0-3).
///
/// - 일반 실행(이 기기에 필사가 있거나 앞서 들어간 적이 있음)은 로컬이 준비되면 곧바로 들어간다. 동기화는 앱 안에서 계속 본다.
/// - 초기 복원(새로 깔았거나 다시 깐 기기에서 로컬이 빔)은 import 성공을 기다리되 **처음부터 「먼저 시작하기」** 를 둔다. 20초 · 60초에는
///   안내만 바꾸고 들어가지 않는다 — 강제 한도는 없다(사용자 결정 2026-09-21). 먼저 시작해도 늦게 도착한 필사는 열린 장에 반영된다
///   (`ChapterCanvasArrivalFeature`).
/// - 판정은 Domain 의 `LaunchWaitRule` 이 한다 — 이 모듈에는 테스트 타깃이 없다.
@Reducer
public struct LaunchProgressFeature {
    @ObservableState
    public struct State {
        /// 재실행 안내(Alert)를 표시할지 여부.
        /// - Note: 마이그레이션 모드가 끝난 시점(`migrationCompleted` · `migrationEndedWithoutImport`)에 true로 설정
        public var shouldShowMigrationAlert: Bool = false
        /// CloudKit 동기화/마이그레이션의 현재 상태.
        public var syncState: PersistentCloudKitContainer.CloudSyncState = .idle
        /// 현재 동기화 과정이 마이그레이션 단계인지 여부를 나타내는 플래그.
        public var isMigration: Bool = false
        /// 이 실행의 대기 방식. 로컬을 세기 전에는 nil — 막힘 · 재실행 요구만 가린다.
        public var mode: LaunchWaitMode?
        /// 초기 복원 대기의 안내 단계(20초 · 60초). 안내만 바꾼다.
        public var stage: LaunchWaitStage = .checking
        /// 사용자가 「먼저 시작하기」 를 눌렀다.
        public var startedFirst = false
        /// 이 설치의 초기 복원이 어떻게 끝났는지 — 한 번 정해지면 다음 실행부터 긴 대기로 돌아가지 않는다.
        @Shared(.appStorage("initialRestoreOutcome")) var initialRestoreOutcome: InitialRestoreOutcome?
        /// 이 설치에서 앞서 들어간 적이 있는가(패치노트가 쓰는 값과 같다).
        @Shared(.appStorage("lastSeenAppVersion")) var lastSeenAppVersion: String?
        /// LaunchProgressFeature에서 사용하는 기본 초기 상태.
        public static let initialState = State()

        /// 지금 시작 화면이 할 일.
        public var route: LaunchRoute { LaunchWaitRule.route(syncState, mode: mode, startedFirst: startedFirst) }
        /// 「먼저 시작하기」 를 보이는가.
        public var offersStartFirst: Bool { LaunchWaitRule.offersStartFirst(syncState, mode: mode) }
    }

    /// CloudKit 동기화 상태를 조회/관찰하기 위한 PersistentCloudKitContainer 의존성.
    @Dependency(\.clouodKitSyncManager) var cloudkitContainer
    /// 로컬에 필사가 있는지 센다 — 초기 복원인지 가린다.
    @Dependency(\.createSwiftDataActor) var database
    @Dependency(\.continuousClock) var clock

    /// 진입 대기 효과의 식별자. 막힘 · 재실행 요구가 오면 기다리던 진입을 끊는다.
    private enum CancelID {
        case enterWriting
        case stage
    }

    public enum Action: ViewAction {
        case view(View)
        case binding
        /// CloudKit 동기화 상태가 변경되었을 때 호출되는 액션.
        case updateSyncState(PersistentCloudKitContainer.CloudSyncState)
        /// 로컬을 세어 이 실행의 대기 방식을 정했다.
        case modeDetermined(LaunchWaitMode)
        /// 초기 복원 대기의 안내 단계가 바뀌었다(20초 · 60초).
        case stageAdvanced(LaunchWaitStage)
        /// 동기화/마이그레이션 관련 처리가 모두 완료되었을 때 상위로 전달하는 액션.
        case syncCompleted

        @CasePathable
        public enum View {
            /// 화면이 처음 등장했을 때 호출.
            /// - Note: CloudKit Sync 상태 관찰 및 초기 동기화를 시작.
            case onAppear
            /// 마이그레이션 완료 알림(Alert) 표시 여부를 업데이트.
            case setMigratioinAlert(Bool)
            /// 「먼저 시작하기」 — 초기 복원을 기다리지 않고 이 기기의 필사로 들어간다.
            case startFirstTapped
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                let hasEnteredBefore = state.lastSeenAppVersion != nil
                let outcome = state.initialRestoreOutcome
                return .merge(
                    .run { send in
                        await send(.binding)
                        await cloudkitContainer.observeCloudKitSyncProgress()
                    },
                    .run { [database] send in
                        // 로컬에 필사가 있는지 — 읽지 못하면 nil(기다리는 쪽으로 본다. 처음부터 「먼저 시작하기」 가 있다).
                        let hasLocalDrawings: Bool?
                        do {
                            hasLocalDrawings = try await database.hasAny(BibleDrawing.self)
                        } catch {
                            Log.error("시작 화면 — 로컬 필사를 세지 못했다. 초기 복원으로 본다", "\(error)")
                            hasLocalDrawings = nil
                        }
                        await send(.modeDetermined(LaunchWaitRule.mode(
                            outcome: outcome, hasEnteredBefore: hasEnteredBefore, hasLocalDrawings: hasLocalDrawings
                        )))
                    }
                )
            case .binding:
                return .run { send in
                    for await syncState in cloudkitContainer.$syncState.values {
                        await send(.updateSyncState(syncState))
                    }
                }
            case .modeDetermined(let mode):
                state.mode = mode
                Log.info("시작 화면 — 대기 방식", "\(mode)")
                let stages: Effect<Action> = mode == .initialRestore ? advanceStages() : .none
                return .merge(stages, evaluate(state: &state))
            case .stageAdvanced(let stage):
                // 안내만 바꾼다 — 들어가지 않는다(사용자 결정 2026-09-21).
                state.stage = max(state.stage, stage)
            case .updateSyncState(let syncState):
                state.syncState = syncState
                return evaluate(state: &state)
            case .view(.startFirstTapped):
                guard state.offersStartFirst else { return .none }
                state.startedFirst = true
                return evaluate(state: &state)
            case .view(.setMigratioinAlert(let isShow)):
                state.shouldShowMigrationAlert = isShow
            default: break
            }
            return .none
        }
    }

    /// 지금 상태 · 대기 방식 · 사용자의 선택으로 할 일을 정한다(`LaunchWaitRule`).
    private func evaluate(state: inout State) -> Effect<Action> {
        switch state.route {
        case .enterWriting:
            // 초기 복원이 어떻게 끝났는지 남긴다 — 다음 실행부터 긴 대기로 돌아가지 않는다.
            if state.initialRestoreOutcome == nil,
               let outcome = LaunchWaitRule.outcome(entering: state.syncState, mode: state.mode, startedFirst: state.startedFirst) {
                state.$initialRestoreOutcome.withLock { $0 = outcome }
            }
            // 사용자가 고른 시작은 기다리지 않는다. 그 밖은 결과 안내를 잠깐 보인 뒤 들어간다.
            let delay: Duration = state.startedFirst ? .zero : .milliseconds(1_500)
            return .merge(
                .cancel(id: CancelID.stage),
                .run { [clock] send in
                    // `try?` 로 삼키면 취소돼도 진입한다 — 취소되면 여기서 끝나야 한다.
                    try await clock.sleep(for: delay)
                    await send(.syncCompleted)
                }
                .cancellable(id: CancelID.enterWriting, cancelInFlight: true)
            )
        case .restartRequired:
            // 지금 상태 전이에서는 진입 결론 뒤에 이 결론이 오지 않는다(`LaunchRouteTesting`). 그래도 기다리던 진입이 있으면 끊는다.
            return .merge(
                .cancel(id: CancelID.enterWriting),
                .cancel(id: CancelID.stage),
                .send(.view(.setMigratioinAlert(true)))
            )
        case .blocked:
            // 로컬 저장소를 쓸 수 없다. 안내만 보이고 들어가지 않는다 (정책 §3 표 4행).
            return .merge(.cancel(id: CancelID.enterWriting), .cancel(id: CancelID.stage))
        case .stay:
            return .none
        }
    }

    /// 초기 복원 대기의 안내를 20초 · 60초에 바꾼다. **들어가지 않는다.**
    private func advanceStages() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: LaunchWaitRule.slowAfter)
            await send(.stageAdvanced(.slow))
            try await clock.sleep(for: LaunchWaitRule.verySlowAfter - LaunchWaitRule.slowAfter)
            await send(.stageAdvanced(.verySlow))
        }
        .cancellable(id: CancelID.stage, cancelInFlight: true)
    }
}
