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

extension ContainerID: DependencyKey {
    public static var liveValue: ContainerID = .initialState
    public static var previewValue: ContainerID = .initialState
    public static var testValue: ContainerID = .initialState
}

extension ModelContainer: @retroactive DependencyKey {
    public static var liveValue: ModelContainer {
        @Dependency(\.containerId) var containerId
        do {
            let url = URL.applicationSupportDirectory.appending(path: containerId.localDBPath)
            let schema = Schema([
                BibleDrawing.self
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
                @Dependency(\.clouodKitSyncManager) var cloudkitContainer
                cloudkitContainer.syncState = .migration
                
                do {
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
    
    public static var previewValue: ModelContainer {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: Schema([BibleDrawing.self]), configurations: config)
        } catch {
            fatalError("Failed to create preview ModelContainer")
        }
    }
    
    public static var testValue: ModelContainer {
        do {
            let url = URL.applicationSupportDirectory.appending(path: "Carve.test.sqlite")
            let schema = Schema([BibleDrawing.self])
            let config = ModelConfiguration(url: url)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create test ModelContainer")
        }
    }
    
}

extension PersistentCloudKitContainer: DependencyKey {
    public static var liveValue = PersistentCloudKitContainer()
    public static var previewValue: PersistentCloudKitContainer = PersistentCloudKitContainer()
    public static var testValue: PersistentCloudKitContainer = PersistentCloudKitContainer()
}


public extension DependencyValues {
    var containerId: ContainerID {
        get { self[ContainerID.self] }
        set { self[ContainerID.self] = newValue }
    }
    
    var modelContainer: ModelContainer {
        get { self[ModelContainer.self] }
        set { self[ModelContainer.self] = newValue }
    }

    /// CloudKit
    var clouodKitSyncManager: PersistentCloudKitContainer {
        get { self[PersistentCloudKitContainer.self] }
        set { self[PersistentCloudKitContainer.self] = newValue }
    }
}




