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
        public var shouldShowMigrationAlert: Bool = false
        public var syncState: PersistentCloudKitContainer.CloudSyncState = .idle
        public var isMigration: Bool = false
        
        public static let initialState = State()
    }
    
    @Dependency(\.clouodKitSyncManager) var cloudkitContainer
    
    
    public enum Action: ViewAction {
        case view(View)
        case binding
        case updateSyncState(PersistentCloudKitContainer.CloudSyncState)
        case syncCompleted

        @CasePathable
        public enum View {
            case onAppear
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
