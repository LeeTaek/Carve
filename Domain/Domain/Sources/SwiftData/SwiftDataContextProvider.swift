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
    ///
    /// **초기 import 를 기다린 결과**다. 시작 화면이 끝나면 더 바뀌지 않을 수 있으므로,
    /// 그 뒤의 주고받음은 ``activity`` 로 본다.
    @Published public var syncState: CloudSyncState = .idle
    /// 앱이 도는 동안 이어지는 동기화 활동 (정책 §4-1).
    @Published public var activity = CloudSyncActivity()
    /// 이벤트 관찰 Task. 앱 수명 동안 유지한다. `nil` 이면 아직 시작하지 않았다.
    private var observationTask: Task<Void, Never>?
    /// 초기 import 를 기다리는 한도(초). 테스트가 줄인다.
    var initialWaitLimit = InitialWaitLimit()
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
    
    /// 초기 import 를 기다리는 한도. 마이그레이션은 오래 걸리므로 따로 둔다.
    struct InitialWaitLimit {
        var normal: Double = 20
        var migration: Double = 120
    }

    /// 계정을 확인하고, 초기 import 의 결론이나 제한 시간까지 기다린다.
    public func observeCloudKitSyncProgress() async {
        // ★ 계정을 조회하기 **전에** 구독을 시작한다. 이전 구현은 계정 조회가 끝난 뒤에야
        //   구독을 열어, 그 사이에 도착한 이벤트를 놓쳤다.
        startObserving()
        self.syncState = (syncState == .migration) ? .migration : .syncing
        let deadline = syncState == .migration ? initialWaitLimit.migration : initialWaitLimit.normal
        // 설정 화면과 같은 조회를 쓴다 — 조회 실패를 "계정 없음" 으로 단정하지 않는 규칙이 한곳에 있다.
        @Dependency(\.cloudAccountStatus) var accountStatus
        do {
            // 계정 조회도 같은 제한 안에서 한다. 이전 구현은 이 호출이 제한 밖이라
            // 계정 조회가 오래 걸리면 기다린 시간이 집계되지 않았다.
            try await Task.withTimeout(seconds: deadline) { [weak self] in
                switch await accountStatus.availability() {
                case .available:
                    break
                case .noAccount, .restricted:
                    throw InitialWaitError.accountUnavailable
                case .unknown, .checking:
                    throw InitialWaitError.accountCheckFailed
                }
                // 조회하는 사이 대기가 취소됐으면 여기서 멈춘다 — 결론을 기다리지 않는다.
                try Task.checkCancellation()
                await self?.waitForInitialConclusion()
            }
        } catch {
            await MainActor.run { self.concludeInitialWait(after: error) }
        }
    }

    /// 초기 대기가 결론 없이 끝난 이유를 상태로 옮긴다 (정책 §3). **이미 결론이 났으면 덮지 않는다.**
    ///
    /// 관찰이 import 결과를 먼저 반영했는데 계정 조회 결과가 뒤늦게 오면, 이전 구현은 그 결론을 지웠다.
    @MainActor
    private func concludeInitialWait(after error: Error) {
        guard let outcome = Self.initialWaitOutcome(after: error) else { return }
        guard syncState.isInProgress else {
            Log.debug("초기 대기 — 이미 결론이 났다. 늦게 온 결과로 덮지 않는다", "\(syncState)", "\(error)")
            return
        }
        syncState = outcome
    }

    /// 초기 대기를 끝낸 오류의 뜻. 순수 함수다.
    ///
    /// | 이유 | 상태 |
    /// |---|---|
    /// | 제한 시간 (`TaskTimeoutError`) | `stillWaiting` — **실패가 아니다.** 관찰은 이어진다 |
    /// | 계정 없음 · 제한 | `failed(.accountUnavailable)` |
    /// | 계정 확인 실패 | `failed(.accountCheckFailed)` — 계정이 없다는 뜻이 아니다 |
    /// | 취소 | nil — 바꾸지 않는다. 기다리던 화면이 사라졌다 |
    /// | 그 밖 | `failed(.unknown)` — 확인하지 못한 오류를 "시간이 걸린다" 로 말하지 않는다 |
    ///
    /// 이전 구현은 계정 조회가 던진 오류와 취소까지 하나의 `catch` 에서 `stillWaiting` 으로 보냈다.
    static func initialWaitOutcome(after error: Error) -> CloudSyncState? {
        switch error {
        case is TaskTimeoutError:
            Log.debug("CloudKit 초기 import 가 제한 시간 안에 끝나지 않았다", "\(error)")
            return .stillWaiting
        case is CancellationError:
            return nil
        case InitialWaitError.accountUnavailable:
            Log.error("iCloud 계정을 쓸 수 없다")
            return .failed(.accountUnavailable)
        case InitialWaitError.accountCheckFailed:
            Log.error("iCloud 계정 상태를 확인하지 못했다")
            return .failed(.accountCheckFailed)
        default:
            Log.error("CloudKit 초기 대기가 알 수 없는 오류로 끝났다", "\(error)")
            return .failed(.unknown)
        }
    }

    /// `eventChangedNotification` 관찰을 **앱 수명 동안** 시작한다. 여러 번 불러도 한 번만 시작한다.
    ///
    /// - Important: 이전 구현은 초기 import 하나를 확인하면 관찰을 끝냈다. 그래서 시작 화면이 지난 뒤의
    ///              동기화 상태를 앱이 전혀 알지 못했다. 이제는 관찰을 끊지 않고 ``activity`` 를 계속 갱신한다.
    public func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            for await notification in notifications {
                guard let self else { return }
                guard let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { continue }
                Log.debug("cloudEvent", cloudEvent.debugDescription)
                await self.receive(Self.syncEvent(from: cloudEvent))
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    /// 관찰을 멈춘다. 앱이 살아 있는 동안은 부를 일이 없고, 테스트·해제 때만 쓴다.
    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// 이벤트 하나를 반영한다. 관찰 Task 가 부른다 — `NSPersistentCloudKitContainer.Event` 는 테스트에서 만들 수 없어
    /// 테스트는 판정에 쓰는 값(`CloudSyncEvent`)으로 여기를 직접 부른다.
    @MainActor
    func receive(_ event: CloudSyncEvent) {
        activity = activity.applying(event, at: Date())
        applyToInitialWait(event)
    }

    /// 시작 화면이 기다리는 `syncState` 에 이벤트를 반영한다.
    ///
    /// 이미 결론이 난 뒤에도 늦게 도착한 import 는 반영한다 — `stillWaiting` 으로 먼저 진입한 사용자에게
    /// 원격 필사가 나중에 도착할 수 있기 때문이다 (정책 §3-1).
    private func applyToInitialWait(_ event: CloudSyncEvent) {
        guard syncState.isInProgress else { return }
        if CloudSyncStateRule.isAwaitedImportSuccess(event) {
            syncState = (syncState == .migration) ? .migrationCompleted : .syncCompleted
        } else if CloudSyncStateRule.isImportFailure(event) {
            syncState = .failed(.importFailed)
        }
    }

    /// 초기 대기가 끝날 때까지 기다린다. 판정은 관찰 Task 가 하고 여기서는 결론만 본다.
    private func waitForInitialConclusion() async {
        for await state in $syncState.values where !state.isInProgress {
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
        
    /// 초기 대기를 멈추게 한 계정 문제. 제한 시간 · 취소와 구분하려고 따로 던진다.
    private enum InitialWaitError: Error {
        /// iCloud 에 로그인돼 있지 않거나 제한됐다.
        case accountUnavailable
        /// 계정 상태를 확인하지 못했다(조회 오류 · 일시적 불가). **없다는 뜻이 아니다.**
        case accountCheckFailed
    }
}
