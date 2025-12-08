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
    public static var liveValue: ModelContainer {
        @Dependency(\.containerId) var containerId
        do {
            let url = URL.applicationSupportDirectory.appending(path: containerId.localDBPath)
            let schema = Schema([
                BibleDrawing.self,
                BiblePageDrawing.self
            ])
            let config = ModelConfiguration(
                url: url,
                cloudKitDatabase: .private(containerId.id)
            )
            return try ModelContainer(for: schema,
                                      migrationPlan: DrawingDataMigrationPlan.self,
                                      configurations: config)
        } catch {
            if let error = error as? SwiftDataError, error == .loadIssueModelContainer {
                /// 기존 컨테이너 로드에 실패한 경우(V1 스키마) 마이그레이션 모드로 전환하여 V1 전용 컨테이너를 구성.
                @Dependency(\.clouodKitSyncManager) var cloudkitContainer
                cloudkitContainer.syncState = .migration
                
                do {
                    /// V1 스키마(DrawingVO)만을 사용하는 ModelContainer를 생성하여 마이그레이션.
                    /// MigrationPlanV1Only: Schema.Version 설정
                    let url = URL.applicationSupportDirectory.appending(path: containerId.localDBPath)
                    let schema = Schema([
                        DrawingVO.self
                    ])
                    let config = ModelConfiguration(
                        url: url,
                        cloudKitDatabase: .private(containerId.id)
                    )
                    cloudkitContainer.syncState = .migration
                    return try ModelContainer(for: schema,
                                              migrationPlan: MigrationPlanV1Only.self,
                                              configurations: config)
                    
                } catch {
                    fatalError("Failed to migration live ModelContainer: \(error.localizedDescription)")
                }
            } else {
                fatalError("Failed to create live ModelContainer: \(error.localizedDescription)")
            }
        }
    }
    
    /// SwiftUI Preview에서 사용할 인메모리 SwiftData ModelContainer.
    public static var previewValue: ModelContainer {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: Schema([
                    BibleDrawing.self,
                    BiblePageDrawing.self
                ]),
                configurations: config)
        } catch {
            fatalError("Failed to create preview ModelContainer")
        }
    }
    
    /// 테스트 코드에서 사용할 SwiftData ModelContainer입니다. (테스트 전용 파일 URL 사용)
    public static var testValue: ModelContainer {
        do {
            let url = URL.applicationSupportDirectory.appending(path: "Carve.test.sqlite")
            let schema = Schema([
                BibleDrawing.self,
                BiblePageDrawing.self
            ])
            let config = ModelConfiguration(url: url)
            return try ModelContainer(for: schema, configurations: config)
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




