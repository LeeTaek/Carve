//
//  SwiftDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import CloudKit
import CoreData
import SwiftData

import Dependencies

public class ContainerID {
    public static var initialState = ContainerID(id: "")
    public var id: String
    public var localDBPath: String
    
    public init(id: String) {
        self.id = id
        self.localDBPath = id.contains("dev") ? "Carve.dev.sqlite" : "Carve.sqlite"
    }
}

public final class PersistentCloudKitContainer: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var syncState: CloudSyncState = .idle
    public var isMigration: Bool = false
    
    public enum CloudSyncState {
        case idle
        case syncing
        case migration
        case success
        case failed
        case nextScene
    }
    
    @Dependency(\.cloudKitDatabase) var cloudKitDB
    
    public init() {}

    public func observeCloudKitSyncProgress() {
        Task {
            do {
                let cloudKitAccountStatus = try await CKContainer.default().accountStatus()
                guard cloudKitAccountStatus == .available else {
                    throw NSError(domain: "CloudKitError", code: 1)
                }
                Task { @MainActor in
                    if self.isMigration {
                        self.syncState = .migration
                        await self.fetchRecordsFromCloudKit()
                    } else {
                        self.syncState = .syncing
                    }
                }
                let operation = CKFetchDatabaseChangesOperation()
                let deadLine: CGFloat = self.isMigration ? 120 : 20

                operation.fetchDatabaseChangesResultBlock = { result in
                    Task { @MainActor in
                        switch result {
                        case .success:
                            Log.debug("CloudKit 동기화 완료")
                            do {
                                try await Task.withTimeout(seconds: deadLine) {
                                    await self.fetchRecordsFromCloudKit()
                                    await self.isSyncFromCloudKit()
                                }
                            } catch {
                                Log.error("⏳ 동기화 시간이 초과됨. 다음 화면으로 진행")
                                self.syncState = .nextScene
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
    
    /// CloudKit에 저장된 필사 데이터 수 반환
    /// - Returns: 저장되어 있는 구절 수
    private func getTotalRecordCountFromCloudKit() async -> Int {
        let query = CKQuery(recordType: "CD_BibleDrawing", predicate: NSPredicate(value: true))
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
    
    
    /// Cloudkit Datafetch Progress 계산을 위한 메서드
    private func fetchRecordsFromCloudKit() async {
        let query = CKQuery(recordType: "CD_BibleDrawing", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = CKQueryOperation.maximumResults
        
        var fetchedCount = 0
        
        Task {
            let totalRecords = await getTotalRecordCountFromCloudKit()
            
            operation.recordMatchedBlock = { _, _ in
                Task { @MainActor in
                    fetchedCount += 1
                    self.progress = totalRecords > 0 ? Double(fetchedCount) / Double(totalRecords) : 1.0
                    if self.progress > 1.0 { self.progress = 1.0 }
                }
            }
            
            operation.queryResultBlock = { _ in
                Log.debug("CloudKit에서 Drawing 데이터 업데이트",  "\(totalRecords)개")
            }
            
            cloudKitDB.add(operation)
        }
    }
    
    
    /// CloudKit DataFetch 완료 여부 notification 구독을 위한 메서드
    private func isSyncFromCloudKit(timeout seconds: UInt64 = 20) async {
        Log.debug("isSyncFromCloudKit")
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let cloudkitNotification = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
        
        for await notification in cloudkitNotification {
            if let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event {
                if let endDate = cloudEvent.endDate , cloudEvent.type == .import {      // CloudKit 이벤트가 끝난 후에 실행
                    Log.debug("cloudKit import event ended at", endDate)
                    
                    await MainActor.run {
                        self.syncState = .success
                    }
                    
                    // 2초 대기후 다음 화면으로 넘어감
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    if !isMigration {
                        await MainActor.run {
                            self.syncState = .nextScene
                        }
                    }
                    return
                }
                
                // ❗️timeout check
                if Date() > deadline {
                    Log.error("⏳ CloudKit sync timeout")
                    await MainActor.run {
                        self.syncState = .nextScene
                    }
                    return
                }
                
            }
        }
    }
    
    public func handleSyncFailure() {
        Task {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                self.syncState = .nextScene
            }
        }
    }
    
}
