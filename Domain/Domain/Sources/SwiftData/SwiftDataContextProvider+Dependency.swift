//
//  SwiftDataContextProvider+Dependency.swift
//  Domain
//
//  Created by 이택성 on 7/17/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import CloudKit
import Foundation
import SwiftData
import ClientInterfaces
import Dependencies

/// ContainerID 주입하기 위한 DependencyKey.
extension ContainerID: DependencyKey {
    public static let liveValue: ContainerID = .initialState
    public static let previewValue: ContainerID = .initialState
    public static let testValue: ContainerID = .initialState
}

/// Carve에서 사용하는 SwiftData ModelContainer를 의존성으로 주입하기 위한 DependencyKey.
extension ModelContainer: @retroactive DependencyKey {
    /// 동기 DependencyKey 접근만으로 private 저장소를 먼저 열지 않도록 기본 경로는 로컬 전용 보류다.
    /// 앱은 계정·ownership preflight 를 마치는 `ReleaseStoreBootstrapper` 로 ModelContainer 를 만든다.
    /// 동기화 상태는 `recordStoreOutcome(_:)` 로 쓴다 — MainActor 격리 상태를 비격리 동기 문맥에서 쓰는 방법은 그 주석에 있다.
    public static var liveValue: ModelContainer {
        @Dependency(\.containerId) var containerId
        @Dependency(\.clouodKitSyncManager) var cloudkitContainer
        @Dependency(\.legacySeparationHoldState) var holdState
        let url = URL.applicationSupportDirectory.appending(path: containerId.localDBPath)
        let preservation = PreservationArea.live(localDBPath: containerId.localDBPath)
        switch LocalStoreLoader.loadForRelease(at: url, cloudKitDatabase: .none, preservation: preservation) {
        case .ready(let container):
            let hold = LegacySeparationHold(reason: .ownershipUnverified)
            holdState.hold = hold
            cloudkitContainer.recordStoreOutcome(.connectionHeld(hold))
            return container
        case .held(let container, let hold):
            /// 연결 보류 — 앱에는 들어가되 이 실행은 이 기기에만 저장한다. 쓰기 · 전체 삭제는 보류 사유로 막힌다(정책 §12-6 C14 ③ · D6).
            holdState.hold = hold
            cloudkitContainer.recordStoreOutcome(.connectionHeld(hold))
            return container
        case .legacyMigration(let container):
            /// V1 로 옮긴 저장소는 재실행해야 앱 스키마로 이어진다. 시작 화면은 이 모드의 어떤 결론에서도 들어가지 않는다.
            cloudkitContainer.recordStoreOutcome(.migration)
            return container
        case .legacyMigrationHeld(let container, let hold):
            /// V1 로 옮겼지만 연결하지 않았다 — 기다릴 import 가 없으니 곧바로 재실행을 요구한다. 다음 실행이 앱 스키마로 옮긴 뒤 다시 판정한다.
            holdState.hold = hold
            cloudkitContainer.recordStoreOutcome(.migrationEndedWithoutImport(nil))
            return container
        case .unavailable(let failure):
            /// 앱은 컨테이너를 쥐어야 하므로 메모리에만 있는 빈 컨테이너를 준다. 시작 화면이 진입을 막는다.
            cloudkitContainer.recordStoreOutcome(.storeUnavailable(failure))
            do {
                return try LocalStoreLoader.makeUnavailableStandIn()
            } catch {
                fatalError("Failed to create stand-in ModelContainer: \(error.localizedDescription)")
            }
        }
    }
    
    /// SwiftUI Preview에서 사용할 인메모리 SwiftData ModelContainer.
    public static var previewValue: ModelContainer {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: AppStoreSchema.schema, configurations: config)
        } catch {
            fatalError("Failed to create preview ModelContainer")
        }
    }
    
    /// 테스트 코드에서 사용할 SwiftData ModelContainer입니다. (테스트 전용 파일 URL 사용)
    public static var testValue: ModelContainer {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: AppStoreSchema.schema, configurations: config)
        } catch {
            fatalError("Failed to create test ModelContainer")
        }
    }
    
}

/// 계정과 로컬 저장소 ownership proof 를 확인한 뒤 앱의 동기화 저장소를 연다.
/// 계정 없음·조회 실패·계정 불일치·판정 불명은 `.none` 으로 열어 기존 필사 읽기와 별도 초안 쓰기만 허용한다.
public enum ReleaseStoreBootstrapper {
    /// 원시 보존 → CloudKit 없는 로컬 마이그레이션 → ownership preflight → 연결 또는 local-only 보류 순으로 시작한다.
    ///
    /// 동기화 상태(`syncManager.syncState`)는 MainActor 에서 쓴다. 함수 전체를 MainActor 로 두지 않고 쓰는 곳만 넘긴다 —
    /// 저장소를 여는 일(보존 · 마이그레이션 · 대체 컨테이너)은 이전처럼 MainActor 밖에서 하고, 상태는 돌아가기 전에 쓴다.
    @discardableResult
    public static func load(
        containerID: ContainerID,
        identity: any CloudAccountIdentityClient,
        ownershipProof: any StoreOwnershipProofClient,
        syncManager: PersistentCloudKitContainer,
        holdState: LegacySeparationHoldState,
        injectsOwnership: Bool = false
    ) async -> ModelContainer {
        let url = URL.applicationSupportDirectory.appending(path: containerID.localDBPath)
        let preservation = PreservationArea.live(localDBPath: containerID.localDBPath)
        switch await LocalStoreLoader.loadForRelease(
            at: url,
            containerID: containerID.id,
            preservation: preservation,
            identity: identity,
            ownershipProof: ownershipProof,
            injectsOwnership: injectsOwnership
        ) {
        case .ready(let container):
            return container
        case .held(let container, let hold):
            holdState.hold = hold
            await MainActor.run { syncManager.syncState = .connectionHeld(hold) }
            return container
        case .legacyMigration(let container):
            await MainActor.run { syncManager.syncState = .migration }
            return container
        case .legacyMigrationHeld(let container, let hold):
            holdState.hold = hold
            await MainActor.run { syncManager.syncState = .migrationEndedWithoutImport(nil) }
            return container
        case .unavailable(let failure):
            await MainActor.run { syncManager.syncState = .storeUnavailable(failure) }
            do {
                return try LocalStoreLoader.makeUnavailableStandIn()
            } catch {
                fatalError("Failed to create stand-in ModelContainer: \(error.localizedDescription)")
            }
        }
    }
}

/// CloudKit 동기화 상태를 관리하는 PersistentCloudKitContainer를 의존성으로 주입하기 위한 키.
///
/// 컨테이너는 MainActor 에 격리된 클래스라 Sendable 이다. 기본값은 의존성을 푸는 비격리 문맥에서 읽으므로 `nonisolated` 다.
extension PersistentCloudKitContainer: DependencyKey {
    public nonisolated static let liveValue = PersistentCloudKitContainer()
    public nonisolated static let previewValue = PersistentCloudKitContainer()
    public nonisolated static let testValue = PersistentCloudKitContainer()
}


private extension PersistentCloudKitContainer {
    /// 동기 기본 경로(`ModelContainer.liveValue`)에서 저장소를 연 결론을 `syncState` 에 남긴다.
    ///
    /// 앱은 `ReleaseStoreBootstrapper` 로 컨테이너를 만들고 `withDependencies` 로 `modelContainer` 를 덮어써서, 앱 시작 경로는 여기를 지나지 않는다.
    /// 이 기본값을 처음 읽는 스레드는 정해져 있지 않다(동기 의존성 접근은 어느 격리에서나 일어난다). 그래서
    /// - 메인 스레드에서 읽혔으면 `MainActor.assumeIsolated` 로 이전처럼 **곧바로** 쓴다 — 쓰는 시점이 그대로다. 메인 스레드임을 방금 확인했다.
    /// - 다른 스레드에서 읽혔으면 MainActor 로 넘겨 쓴다 — 이전에는 그 스레드에서 바로 써 MainActor 의 읽기와 경합했다.
    ///   메인 스레드를 막는 `DispatchQueue.main.sync` 는 메인 스레드가 이 접근을 기다리면 멈추므로 쓰지 않는다.
    nonisolated func recordStoreOutcome(_ state: CloudSyncState) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { syncState = state }
        } else {
            Task { @MainActor in self.syncState = state }
        }
    }
}

public extension DependencyValues {
    /// 현재 CloudKit 컨테이너 ID 및 로컬 DB 경로를 나타내는 의존성.
    var containerId: ContainerID {
        get { self[ContainerID.self] }
        set { self[ContainerID.self] = newValue }
    }
    
    /// SwiftData ModelContainer 인스턴스를 주입받기 위한 의존성.
    var modelContainer: ModelContainer {
        get { self[ModelContainer.self] }
        set { self[ModelContainer.self] = newValue }
    }

    /// CloudKit 동기화 진행 상태를 조회/갱신하기 위한 PersistentCloudKitContainer 의존성.
    var clouodKitSyncManager: PersistentCloudKitContainer {
        get { self[PersistentCloudKitContainer.self] }
        set { self[PersistentCloudKitContainer.self] = newValue }
    }
}


