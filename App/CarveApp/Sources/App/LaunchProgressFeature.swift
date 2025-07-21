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
        public var syncProgress: Double = 0.0
        public var syncState: PersistentCloudKitContainer.CloudSyncState = .idle
        public var isMigration: Bool = false
        
        public static let initialState = State()
    }
    
    @Dependency(\.clouodKitSyncManager) var cloudkitContainer
    
    
    public enum Action: ViewAction {
        case view(View)
        case binding
        case updateProgress(Double)
        case updateSyncState(PersistentCloudKitContainer.CloudSyncState)
        case faliedSyncCloudkit
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
                cloudkitContainer.observeCloudKitSyncProgress()
                return .run { send in
                    await send(.binding)
                }
            case .binding:
                
                return .run { send in
                    async let progressStream: Void = {
                        for await progress in cloudkitContainer.$progress.values {
                            Log.debug("progress", progress)
                            await send(.updateProgress(progress))
                        }
                    }()
                    async let syncStateStream: Void = {
                        for await syncState in cloudkitContainer.$syncState.values {
                            await send(.updateSyncState(syncState))
                        }
                    }()
                    
                    _ = await (progressStream, syncStateStream)
                }
            case .updateProgress(let progress):
                state.syncProgress = progress
            case .updateSyncState(let syncState):
                state.syncState = syncState
                if syncState == .failed {
                    return .send(.faliedSyncCloudkit)
                }
                if syncState == .success && state.isMigration {
                    return .send(.view(.setMigratioinAlert(true)))
                }
                if syncState == .nextScene {
                    return .send(.syncCompleted)
                }
            case .view(.setMigratioinAlert(let isShow)):
                state.shouldShowMigrationAlert = isShow
            case .faliedSyncCloudkit:
                cloudkitContainer.handleSyncFailure()
            default: break
            }
            return .none
        }
    }
}
