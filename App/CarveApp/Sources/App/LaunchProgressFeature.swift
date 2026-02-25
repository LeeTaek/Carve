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
        /// 데이터 마이그레이션 완료 알림(Alert)을 표시할지 여부.
        /// - Note: `CloudSyncState.migrationCompleted` 시점에 true로 설정
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
                switch syncState {
                case .failed:
                    return .run { send in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await send(.syncCompleted)
                    }
                case .migrationCompleted:
                    return .send(.view(.setMigratioinAlert(true)))
                case .syncCompleted:
                    return .run { send in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await send(.syncCompleted)
                    }
                default: break
                }
            case .view(.setMigratioinAlert(let isShow)):
                state.shouldShowMigrationAlert = isShow
            default: break
            }
            return .none
        }
    }
}
