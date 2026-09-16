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
    ///
    /// - Important: **기준 시간이 지난 것과 실패한 것을 같은 상태로 두지 않는다**(정책 §3).
    ///              `stillWaiting` 은 안내 문구를 바꾸는 신호일 뿐 실패가 아니며, `failed` 는
    ///              확인된 오류가 있을 때만 쓴다.
    public enum CloudSyncState: Equatable, Sendable {
        /// 동기화를 수행하지 않는 대기 상태.
        case idle
        /// CloudKit와 동기화 작업을 진행 중인 상태.
        case syncing
        /// 초기 import 가 **성공으로** 끝난 상태.
        case syncCompleted
        /// 마이그레이션 모드로 동기화를 진행 중인 상태.
        case migration
        /// 마이그레이션 모드 동기화가 완료된 상태.
        case migrationCompleted
        /// 기준 시간이 지났다. **실패가 아니다** — 관찰은 계속되고 원격 필사가 나중에 도착할 수 있다.
        case stillWaiting
        /// 확인된 오류로 멈췄다. 원인을 함께 들고 다녀야 화면이 맞는 안내를 한다.
        case failed(CloudSyncFailure)

        /// 아직 결론이 나지 않아 **관찰이 이어지는** 상태인가. 진행 표시를 켤지 정하는 데 쓴다.
        /// `stillWaiting` 은 제한 시간이 지났을 뿐 관찰이 끝난 것이 아니므로 여기 포함된다.
        public var isInProgress: Bool {
            switch self {
            case .idle, .syncing, .migration, .stillWaiting: true
            case .syncCompleted, .migrationCompleted, .failed: false
            }
        }
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
        let deadline: Double = syncState == .migration ? 120 : 20
        do {
            // 계정 조회도 같은 제한 안에서 한다. 이전 구현은 이 호출이 제한 밖이라
            // 계정 조회가 오래 걸리면 기다린 시간이 집계되지 않았다.
            try await Task.withTimeout(seconds: deadline) { [weak self] in
                let cloudKitAccountStatus = try await CKContainer.default().accountStatus()
                guard cloudKitAccountStatus == .available else {
                    throw CloudkitError.accountError
                }
                try await self?.isSyncFromCloudKit()
            }
        } catch let error as CloudkitError {
            await MainActor.run { self.syncState = Self.state(for: error) }
        } catch {
            // 제한 시간이 지난 것은 **실패가 아니다.** 관찰을 끊지 않고 안내만 바꾼다.
            Log.debug("CloudKit 초기 import 가 제한 시간 안에 끝나지 않았다", error.localizedDescription)
            await MainActor.run { self.syncState = .stillWaiting }
        }
    }

    /// 확인된 오류를 상태로 옮긴다. 원인을 잃지 않아야 화면이 맞는 안내를 한다.
    private static func state(for error: CloudkitError) -> CloudSyncState {
        switch error {
        case .accountError:
            Log.error("iCloud 계정을 쓸 수 없다", "\(error)")
            return .failed(.accountUnavailable)
        case .syncingFail:
            Log.error("CloudKit import 가 오류로 끝났다", "\(error)")
            return .failed(.importFailed)
        case .initFail, .timeout:
            Log.error("CloudKit 초기화 실패", "\(error)")
            return .failed(.unknown)
        }
    }
    
    
    /// `eventChangedNotification` 을 구독해 초기 import 가 **성공으로** 끝나는지 본다.
    ///
    /// - Important: 끝난 것과 성공한 것은 다르다. 이전 구현은 `endDate != nil` 과 `type == .import` 만 보고
    ///              완료로 판정해서 **오류로 끝난 import 도 "동기화 완료" 로 표시**했다. 판정은
    ///              `CloudSyncStateRule` 이 하고 여기서는 이벤트를 값으로 바꿔 넘기기만 한다.
    /// - Throws: import 가 오류로 끝나면 `CloudkitError.syncingFail`. 제한 시간 초과는 호출부가 다룬다.
    private func isSyncFromCloudKit() async throws {
        let cloudkitNotification = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)

        for await notification in cloudkitNotification {
            guard let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { continue }
            Log.debug("cloudEvent", cloudEvent.debugDescription)

            let event = Self.syncEvent(from: cloudEvent)
            guard CloudSyncStateRule.concludesWaiting(event) else { continue }

            if CloudSyncStateRule.isImportFailure(event) {
                throw CloudkitError.syncingFail
            }
            await MainActor.run {
                self.syncState = (self.syncState == .migration) ? .migrationCompleted : .syncCompleted
            }
            return
        }
    }

    /// CloudKit 이벤트를 판정에 필요한 값만 남긴 `CloudSyncEvent` 로 바꾼다.
    private static func syncEvent(from event: NSPersistentCloudKitContainer.Event) -> CloudSyncEvent {
        let kind: CloudSyncEvent.Kind = switch event.type {
        case .setup: .setup
        case .import: .cloudImport
        case .export: .cloudExport
        @unknown default: .setup
        }
        return CloudSyncEvent(kind: kind, ended: event.endDate != nil, succeeded: event.succeeded)
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
