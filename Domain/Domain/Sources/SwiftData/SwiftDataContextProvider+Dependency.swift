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
    public static var liveValue: ContainerID = .initialState
    public static var previewValue: ContainerID = .initialState
    public static var testValue: ContainerID = .initialState
}

/// Carve에서 사용하는 SwiftData ModelContainer를 의존성으로 주입하기 위한 DependencyKey.
extension ModelContainer: @retroactive DependencyKey {
    /// 실제 앱 환경에서 사용할 SwiftData ModelContainer.
    /// - CloudKit Private DB와 연동되며, 로컬 파일 URL과 마이그레이션 플랜(DrawingDataMigrationPlan)을 함께 구성.
    /// - 열기 전에 원시 사본을 뜬다(정책 §12-6 C3 ①). 뜨지 못하면 열지 않고 시작 화면에서 막는다.
    /// - 열지 못하면 `LocalStoreLoader` 가 **V1 폴백 전에** 메타데이터로 저장소를 가린다. 확인된 1.0.x 저장소만 V1 전용 컨테이너로
    ///   옮기고(마이그레이션 모드), 그 밖은 V1 폴백 없이 시작 화면에서 막는다 (정책 §3 표 4행 · 테스트 계획 MIG-F1).
    public static var liveValue: ModelContainer {
        @Dependency(\.containerId) var containerId
        @Dependency(\.clouodKitSyncManager) var cloudkitContainer
        let url = URL.applicationSupportDirectory.appending(path: containerId.localDBPath)
        let preservation = PreservationArea.live(localDBPath: containerId.localDBPath)
        switch LocalStoreLoader.load(at: url, cloudKitDatabase: .private(containerId.id), preservation: preservation) {
        case .ready(let container):
            return container
        case .legacyMigration(let container):
            /// V1 로 옮긴 저장소는 재실행해야 앱 스키마로 이어진다. 시작 화면은 이 모드의 어떤 결론에서도 들어가지 않는다.
            cloudkitContainer.syncState = .migration
            return container
        case .unavailable(let failure):
            /// 앱은 컨테이너를 쥐어야 하므로 메모리에만 있는 빈 컨테이너를 준다. 시작 화면이 진입을 막는다.
            cloudkitContainer.syncState = .storeUnavailable(failure)
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

/// CloudKit 동기화 상태를 관리하는 PersistentCloudKitContainer를 의존성으로 주입하기 위한 키.
extension PersistentCloudKitContainer: DependencyKey {
    public static var liveValue = PersistentCloudKitContainer()
    public static var previewValue: PersistentCloudKitContainer = PersistentCloudKitContainer()
    public static var testValue: PersistentCloudKitContainer = PersistentCloudKitContainer()
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




