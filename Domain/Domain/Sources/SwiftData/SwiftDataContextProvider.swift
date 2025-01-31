//
//  SwiftDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation
import SwiftData
import CloudKit

import Dependencies

public final class PersistentCloudKitContainer: ObservableObject {
    private enum ContainerType {
        case live
        case test
        case preview
    }
    public static let shared = PersistentCloudKitContainer(type: .live)
    public static let test = PersistentCloudKitContainer(type: .test)
    public static let preview = PersistentCloudKitContainer(type: .preview)
    public let container: ModelContainer
    
    @Published public var progress: Double = 0.0
    
    private init(type: ContainerType) {
        switch type {
        case .live, .test:
            let path = if type == .live { "Carve.sqlite" } else { "Carve.test.sqlite" }
            do {
                let url = URL.applicationSupportDirectory.appending(path: path)
                let schema = Schema([
                    BibleDrawing.self
                ])
                let config = ModelConfiguration(
                    url: url,
                    cloudKitDatabase: .private("iCloud.Carve.SwiftData.iCloud")
                )
                container = try ModelContainer(for: schema, configurations: config)
                
                observeCloudKitSyncProgress()
            } catch {
                fatalError("Failed to create SwiftData container")
            }
        case .preview:
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: Schema([BibleDrawing.self]), configurations: config)
            } catch {
                fatalError("Failed to create SwiftData container on Preview")
            }
        }
    }
    
    private func observeCloudKitSyncProgress() {
        Task {
            let cloudKitDB = CKContainer(identifier: "iCloud.Carve.SwiftData.iCloud").privateCloudDatabase
            let operation = CKFetchDatabaseChangesOperation()
            var changedZoneCount = 0

            operation.recordZoneWithIDChangedBlock = { recordZoneID in
                Task { @MainActor in
                    Log.debug("✅ 변경된 레코드 존 ID: \(recordZoneID.zoneName)")
                    changedZoneCount += 1
                    self.progress += 0.1
                    if self.progress > 1.0 { self.progress = 1.0 }
                }
            }
            
            operation.fetchDatabaseChangesResultBlock = { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        Log.debug("✅ CloudKit 동기화 완료, 변경된 존 개수: \(changedZoneCount)")
                        self.progress = 1.0
                    case .failure(let error):
                        Log.error("❌ CloudKit 동기화 중 오류 발생: \(error.localizedDescription)")
                    }
                }
            }
            cloudKitDB.add(operation)
        }
    }
}
