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

extension CKDatabase: @retroactive DependencyKey {
    public static var liveValue: CKDatabase {
        CKContainer(identifier: "iCloud.Carve.SwiftData.iCloud").privateCloudDatabase
    }
}

extension ModelContainer: @retroactive DependencyKey {
    public static var liveValue: ModelContainer {
        do {
            let url = URL.applicationSupportDirectory.appending(path: "Carve.sqlite")
            let schema = Schema([
                BibleDrawing.self
            ])
            let config = ModelConfiguration(
                url: url,
                cloudKitDatabase: .private("iCloud.Carve.SwiftData.iCloud")
            )
            return try ModelContainer(for: schema,
                                      migrationPlan: DrawingDataMigrationPlan.self,
                                      configurations: config)
        } catch {
            do {
                let url = URL.applicationSupportDirectory.appending(path: "Carve.sqlite")
                let schema = Schema([
                    DrawingVO.self
                ])
                let config = ModelConfiguration(
                    url: url,
                    cloudKitDatabase: .private("iCloud.Carve.SwiftData.iCloud")
                )
                return try ModelContainer(for: schema,
                                          migrationPlan: MigrationPlanV1Only.self,
                                          configurations: config)
            } catch {
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

public extension DependencyValues {
    var container: ModelContainer {
        get { self[ModelContainer.self] }
        set { self[ModelContainer.self] = newValue }
    }
    
    var cloudkitDB: CKDatabase {
        get { self[CKDatabase.self] }
        set { self[CKDatabase.self] = newValue }
    }
}




