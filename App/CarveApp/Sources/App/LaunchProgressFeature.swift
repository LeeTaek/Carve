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
        /// LaunchProgressFeature에서 사용하는 기본 초기 상태.
        public static let initialState = State()
    }
    
    /// CloudKit 동기화 상태를 조회/관찰하기 위한 PersistentCloudKitContainer 의존성.
    @Dependency(\.clouodKitSyncManager) var cloudkitContainer

    /// 진입 대기 효과의 식별자. 막힘 · 재실행 요구가 오면 기다리던 진입을 끊는다.
    private enum CancelID {
        case enterWriting
    }

    public enum Action: ViewAction {
        case view(View)
        case binding
        /// CloudKit 동기화 상태가 변경되었을 때 호출되는 액션.
        case updateSyncState(PersistentCloudKitContainer.CloudSyncState)
        /// 동기화/마이그레이션 관련 처리가 모두 완료되었을 때 상위로 전달하는 액션.
        case syncCompleted

        @CasePathable
        public enum View {
            /// 화면이 처음 등장했을 때 호출.
            /// - Note: CloudKit Sync 상태 관찰 및 초기 동기화를 시작.
            case onAppear
            /// 마이그레이션 완료 알림(Alert) 표시 여부를 업데이트.
            case setMigratioinAlert(Bool)
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                return .run { send in
                    await send(.binding)
                    await cloudkitContainer.observeCloudKitSyncProgress()
                }
            case .binding:
                return .run { send in
                    for await syncState in cloudkitContainer.$syncState.values {
                        await send(.updateSyncState(syncState))
                    }
                }
            case .updateSyncState(let syncState):
                state.syncState = syncState
                // 들어갈지는 Domain 의 `launchRoute` 가 정한다 — 이 모듈에는 테스트 타깃이 없다 (테스트 계획 MIG-F1).
                switch syncState.launchRoute {
                case .enterWriting:
                    // `failed` · `stillWaiting` · `syncCompleted` 셋 다 "이 화면을 떠난다" 는 같지만 **안내 문구가 다르다**.
                    // 특히 `stillWaiting` 은 실패가 아니라 기다리는 중이며, 원격 필사가 나중에 도착할 수 있다.
                    return .run { send in
                        // `try?` 로 삼키면 취소돼도 진입한다 — 취소되면 여기서 끝나야 한다.
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                        await send(.syncCompleted)
                    }
                    .cancellable(id: CancelID.enterWriting)
                case .restartRequired:
                    // 지금 상태 전이에서는 진입 결론 뒤에 이 결론이 오지 않는다(`LaunchRouteTesting`). 그래도 기다리던 진입이 있으면 끊는다.
                    return .merge(
                        .cancel(id: CancelID.enterWriting),
                        .send(.view(.setMigratioinAlert(true)))
                    )
                case .blocked:
                    // 로컬 저장소를 쓸 수 없다. 안내만 보이고 들어가지 않는다 (정책 §3 표 4행).
                    return .cancel(id: CancelID.enterWriting)
                case .stay:
                    break
                }
            case .view(.setMigratioinAlert(let isShow)):
                state.shouldShowMigrationAlert = isShow
            default: break
            }
            return .none
        }
    }
}
