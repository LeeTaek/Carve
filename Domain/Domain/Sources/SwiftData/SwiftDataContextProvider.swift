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
    @Published public var syncState: CloudSyncState = .idle
    private var currentTitle: TitleVO
    private lazy var cloudKitDB: CKDatabase = {
        @Dependency(\.containerId) var containerId
        return CKContainer(identifier: containerId.id).privateCloudDatabase
    }()
    
    @Dependency(\.drawingData) private var drawingDatabase
    
    public enum CloudSyncState {
        case idle
        case syncing
        case syncCompleted
        case migration
        case migrationCompleted
        case failed
    }
    
    init() {
        // 현재 장 Fetch
        if let titleData = UserDefaults.standard.data(forKey: "title"),
           let decodedTitle = try? JSONDecoder().decode(TitleVO.self, from: titleData) {
            self.currentTitle = decodedTitle
        } else {
            self.currentTitle = .initialState
        }
    }
    
    /// CloudKit 동기화 상태를 확인하고, 동기화 진행 상태에 따라 적절한 처리를 수행
    public func observeCloudKitSyncProgress() async {
        self.syncState = (syncState == .migration) ? .migration : .syncing
        do {
            // iCloud 계정상태 확인
            let cloudKitAccountStatus = try await CKContainer.default().accountStatus()
            guard cloudKitAccountStatus == .available else {
                throw CloudkitError.accountError
            }
            
            // cloudKit to local로 import 작업 수행
            let deadline: Double = syncState == .migration ? 120 : 20
            try await self.isSyncFromCloudKit(deadline: deadline)
        } catch {
            Log.error("CloudKit 초기화 실패, 네트워크 or iCloud 계정 확인 필요", error.localizedDescription)
            await MainActor.run {
                self.syncState = .failed
            }
        }
    }
    
    
    /// CloudKit sync 완료 여부 notification 구독을 위한 메서드
    /// 지정 시간 내에  .import를 수신하면 동기화 완료 처리
    private func isSyncFromCloudKit(deadline seconds: Double) async throws {
        try await Task.withTimeout(seconds: seconds) {
            let cloudkitNotification = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            
            for await notification in cloudkitNotification {
                if let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event {
                    Log.debug("cloudEvent", cloudEvent.debugDescription)
                    if cloudEvent.endDate != nil , cloudEvent.type == .import {      // CloudKit 이벤트가 끝난 후에 실행
                        await MainActor.run {
                            self.syncState = (self.syncState == .migration) ? .migrationCompleted : .syncCompleted
                        }
                        return
                    }
                }
            }
            throw CloudkitError.timeout
        }
    }
        
    private enum CloudkitError: Error {
        case initFail
        case timeout
        case syncingFail
        case accountError
    }
}
