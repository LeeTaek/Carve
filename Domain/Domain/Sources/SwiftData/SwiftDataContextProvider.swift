//
//  SwiftDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import CloudKit
import CoreData
import SwiftData

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
    private let cloudKitDB = CKContainer(identifier: "iCloud.Carve.SwiftData.iCloud").privateCloudDatabase
    
    @Published public var progress: Double = 0.0
    @Published public var syncState: CloudSyncState = .idle
    
    public enum CloudSyncState {
        case idle
        case syncing
        case success
        case failed
        case next
    }
    
    private init(type: ContainerType) {
        switch type {
        case .live, .test:
            let path = if type == .live { "Carve.sqlite" } else { "Carve.test.sqlite" }
            do {
                let url = URL.applicationSupportDirectory.appending(path: path)
                let schema = Schema([
                    DrawingVO.self
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
                container = try ModelContainer(for: Schema([DrawingVO.self]), configurations: config)
            } catch {
                fatalError("Failed to create SwiftData container on Preview")
            }
        }
    }
    
    private func observeCloudKitSyncProgress() {
        Task {
            do {
                let cloudKitAccountStatus = try await CKContainer.default().accountStatus()
                guard cloudKitAccountStatus == .available else {
                    throw NSError(domain: "CloudKitError", code: 1)
                }
                Task { @MainActor in
                    self.syncState = .syncing
                }
                let operation = CKFetchDatabaseChangesOperation()
                
                operation.fetchDatabaseChangesResultBlock = { result in
                    Task { @MainActor in
                        switch result {
                        case .success:
                            Log.debug("CloudKit 동기화 완료")
                            do {
                                try await Task.withTimeout(seconds: 5) {
                                    await self.fetchRecordsFromCloudKit()
                                    await self.isSyncFromCloudKit()
                                }
                            } catch {
                                Log.error("⏳ 동기화 시간이 초과됨. 다음 화면으로 진행")
                                self.syncState = .next
                            }
                        case .failure(let error):
                            Log.error("CloudKit 동기화 중 오류 발생", error.localizedDescription)
                            throw NSError(domain: "CloudKitError", code: 1)
                        }
                    }
                }
                cloudKitDB.add(operation)
            } catch {
                Log.error("CloudKit 초기화 실패, 네트워크 or iCloud 계정 확인 필요", error.localizedDescription)
                await MainActor.run {
                    self.syncState = .failed
                }
            }
        }
    }
    
    private func getTotalRecordCountFromCloudKit() async -> Int {
        let query = CKQuery(recordType: "CD_DrawingVO", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = CKQueryOperation.maximumResults
        
        return await withCheckedContinuation { continuation in
            var totalRecords = 0
            var hasResumed = false
            
            operation.recordMatchedBlock = { _, result in
                if case .success = result {
                    totalRecords += 1
                }
            }
            operation.queryResultBlock = { _ in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: totalRecords)
                }
            }
            cloudKitDB.add(operation)
        }
    }
    
    private func fetchRecordsFromCloudKit() async {
        let query = CKQuery(recordType: "CD_DrawingVO", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = CKQueryOperation.maximumResults
        
        var fetchedCount = 0
        let totalRecords = await getTotalRecordCountFromCloudKit()
        
        operation.recordMatchedBlock = { _, _ in
            Task { @MainActor in
                fetchedCount += 1
                self.progress = Double(fetchedCount) / Double(totalRecords)
                if self.progress > 1.0 { self.progress = 1.0 }
            }
        }
        
        operation.queryResultBlock = { _ in
            Log.debug("CloudKit에서 Drawing 데이터 업데이트",  "\(totalRecords)개")
        }
        
        cloudKitDB.add(operation)
    }
    
    private func isSyncFromCloudKit() async {
        Log.debug("isSyncFromCloudKit")
        let cloudkitNotification = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
        for await notification in cloudkitNotification {
            if let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event {
                if cloudEvent.endDate != nil {      // CloudKit 이벤트가 끝난 후에 실행
                    Log.info("end of CloudKit event")
                    Task { @MainActor in
                        if cloudEvent.succeeded {
                            Log.info("CloudKit sync succeeded", cloudEvent.type)
                            self.syncState = .success
                        } else {
                            Log.info("SyncFailed!")
                            self.syncState = .failed
                        }
                        
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.syncState = .next
                        if let error = cloudEvent.error {
                            Log.error("Error: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    public func handleSyncFailure() {
        Task {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                self.syncState = .next
            }
        }
    }
    
}
