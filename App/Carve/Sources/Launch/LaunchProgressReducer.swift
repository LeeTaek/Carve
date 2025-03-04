//
//  LaunchProgressReducer.swift
//  Carve
//
//  Created by 이택성 on 2/12/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Domain

import ComposableArchitecture

@Reducer
struct LaunchProgressReducer {
    @ObservableState
    struct State {
        var cloudProgress: Double = 0.0
        var cacheProgress: Double = 0.0
        var launchState: LaunchState {
            if cacheProgress < 1.0 {
                return .caching
            } else if cloudProgress < 1.0 {
                return .cloudSync
            } else {
                return .completed
            }
        }
        static var initialState: Self = .init()
    }
    
    @Dependency(\.lastVerseCache) var lastVerseCache
    
    enum Action {
        case startSync
        case updateCloudProgress(Double)
        case observeCacheProgress
        case cachingComplete
        case updateCacheProgress(Double)
        case observeCloudKitSync
        case cloudSyncComplete
    }
    
    enum LaunchState {
        case caching
        case cloudSync
        case completed
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startSync:
                return .run { send in
                    let cloudKitContainer = PersistentCloudKitContainer.shared
            
                    await send(.updateCloudProgress(cloudKitContainer.progress))
                    await lastVerseCache.loadCache()
                    await send(.observeCacheProgress)
                }
            case .observeCacheProgress:
                return .run { send in
                    for await progress in await lastVerseCache.progressStream {
                        Log.debug("캐싱 진행", progress)
                        await send(.updateCacheProgress(progress))
                    }
                    await send(.cachingComplete)
                }
            case .updateCacheProgress(let progress):
                Log.debug("캐싱", progress)
                state.cacheProgress = progress
            case .cachingComplete:
                Log.debug("캐싱 완료")
                state.cacheProgress = 1.0
                state.cloudProgress = 0.0
                return .send(.observeCloudKitSync)
            case .observeCloudKitSync:
                return .run { send in
                    let cloudKitContainer = PersistentCloudKitContainer.shared
                    Log.debug("클라우드 동기화 시작")
                    for await isSyncing in cloudKitContainer.$isSyncing.values where isSyncing {
                        await send(.cloudSyncComplete)
                    }
                }
            case .updateCloudProgress(let progress):
                state.cloudProgress = progress
            case .cloudSyncComplete:
                Log.debug("클라우드 동기화 완료")
                state.cloudProgress = 1.0
            }
            return .none
        }
    }
}
