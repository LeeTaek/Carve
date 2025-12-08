//
//  PersistentCloudKitContainer.swift
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

/// CloudKit 컨테이너 식별자와 로컬 SwiftData DB 파일 경로를 관리.
public class ContainerID {
    /// 기본값(초기 상태)로 사용하는 ContainerID. 실제 컨테이너 ID는 앱 시작 시 주입.
    public static var initialState = ContainerID(id: "")
    public var id: String
    /// 로컬 SwiftData SQLite 파일 경로. dev/prod 여부에 따라 경로 설정.
    public var localDBPath: String
    
    public init(id: String) {
        self.id = id
        self.localDBPath = id.contains("dev") ? "Carve.dev.sqlite" : "Carve.sqlite"
    }
}

/// CloudKit 동기화 상태를 관리하는 컨테이너 객체.
/// SwiftData와 NSPersistentCloudKitContainer 이벤트를 관찰하여 동기화 진행 상태를 표현.
public final class PersistentCloudKitContainer: ObservableObject {
    /// 현재 CloudKit 동기화 상태. LaunchProgressFeature에서 구독하여 사용.
    @Published public var syncState: CloudSyncState = .idle
    /// 현재 동기화 기준이 되는 성경 제목/장 정보.
    private var currentTitle: BibleChapter
    /// 의존성으로 주입된 ContainerID를 기반으로 생성되는 CloudKit Private 데이터베이스.
    private lazy var cloudKitDB: CKDatabase = {
        @Dependency(\.containerId) var containerId
        return CKContainer(identifier: containerId.id).privateCloudDatabase
    }()
    
    /// 필사 데이터를 조회/저장하기 위해 주입된 SwiftData 래퍼.
    @Dependency(\.drawingData) private var drawingDatabase
    
    /// CloudKit 동기화 진행 상태.
    public enum CloudSyncState {
        /// 동기화를 수행하지 않는 대기 상태.
        case idle
        /// CloudKit와 동기화 작업을 진행 중인 상태.
        case syncing
        /// 일반 동기화 작업이 정상적으로 완료된 상태.
        case syncCompleted
        /// 마이그레이션 모드로 동기화를 진행 중인 상태.
        case migration
        /// 마이그레이션 모드 동기화가 완료된 상태.
        case migrationCompleted
        /// 네트워크/계정 문제 등으로 동기화가 실패한 상태.
        case failed
    }
    
    init() {
        // 현재 장 Fetch
        if let titleData = UserDefaults.standard.data(forKey: "title"),
           let decodedTitle = try? JSONDecoder().decode(BibleChapter.self, from: titleData) {
            self.currentTitle = decodedTitle
        } else {
            self.currentTitle = .initialState
        }
    }
    
    /// CloudKit 동기화 상태를 확인하고, 계정 상태/네트워크 등을 검사한 뒤 동기화를 시작.
    /// - 동기화 모드에 따라 타임아웃(deadline)을 다르게 적용.
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
    
    
    /// NSPersistentCloudKitContainer.eventChangedNotification을 구독하여
    /// 지정된 시간(deadline) 내에 .import 이벤트가 완료되는지를 검사.
    /// - Parameter seconds: 동기화 완료를 기다릴 최대 시간(초).
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
        
    /// CloudKit 초기화 및 동기화 과정에서 발생할 수 있는 에러.
    private enum CloudkitError: Error {
        /// 컨테이너 초기화에 실패.
        case initFail
        /// 지정된 대기 시간 내에 동기화 완료 이벤트를 받지 못한 경우.
        case timeout
        /// 동기화 처리 중 알 수 없는 오류가 발생한 경우.
        case syncingFail
        /// iCloud 계정 상태가 유효하지 않은 경우. (비로그인, 제한 등)
        case accountError
    }
}
