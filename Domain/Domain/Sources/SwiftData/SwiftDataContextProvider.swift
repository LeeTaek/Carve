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
    /// 알림 구독. 앱 수명 동안 유지한다. `nil` 이면 아직 시작하지 않았다. **MainActor 에서만** 바꾼다.
    private var observation: Observation?
    /// 초기 대기를 이미 시작했는가. 두 번째 호출이 결론을 되돌리지 않게 한다. **MainActor 에서만** 바꾼다.
    private var initialWaitStarted = false
    /// 초기 import 를 기다리는 한도(초). 테스트가 줄인다.
    var initialWaitLimit = InitialWaitLimit()
    /// 관찰할 알림. 테스트가 바꾼다 — `NSPersistentCloudKitContainer.Event` 는 테스트에서 만들 수 없다.
    var eventSource = EventSource()
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
        /// 마이그레이션 모드의 대기가 import 성공 없이 끝났다. 원인이 `nil` 이면 제한 시간이 지났다.
        ///
        /// 일반 모드의 `failed` · `stillWaiting` 과 달리 **들어가지 않고 재실행을 요구한다** — 이번 실행의 저장소는
        /// V1 전용 컨테이너라 필사를 저장할 수 없다(테스트 계획 MIG-F1).
        case migrationEndedWithoutImport(CloudSyncFailure?)
        /// 기준 시간이 지났다. **실패가 아니다** — 관찰은 계속되고 원격 필사가 나중에 도착할 수 있다.
        case stillWaiting
        /// 확인된 오류로 멈췄다. 원인을 함께 들고 다녀야 화면이 맞는 안내를 한다.
        case failed(CloudSyncFailure)
        /// 로컬 저장소를 쓸 수 없다. CloudKit 을 기다리지 않고 **들어가지 않는다** (정책 §3 표 4행).
        /// 오프라인 · 계정 문제(`failed`)와 다른 축이다.
        case storeUnavailable(LocalStoreFailure)

        /// 아직 결론이 나지 않아 **관찰이 이어지는** 상태인가. 진행 표시를 켤지 정하는 데 쓴다.
        /// `stillWaiting` 은 제한 시간이 지났을 뿐 관찰이 끝난 것이 아니므로 여기 포함된다.
        public var isInProgress: Bool {
            switch self {
            case .idle, .syncing, .migration, .stillWaiting: true
            case .syncCompleted, .migrationCompleted, .migrationEndedWithoutImport, .failed, .storeUnavailable: false
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
    
    /// 관찰할 알림과, 그 알림에서 판정에 쓸 이벤트를 꺼내는 방법.
    struct EventSource: Sendable {
        var center: NotificationCenter = .default
        var name: Notification.Name = NSPersistentCloudKitContainer.eventChangedNotification
        var event: @Sendable (Notification) -> CloudSyncEvent? = { PersistentCloudKitContainer.cloudKitEvent(from: $0) }
    }

    /// 초기 import 를 기다리는 한도. 마이그레이션은 오래 걸리므로 따로 둔다.
    struct InitialWaitLimit {
        var normal: Double = 20
        var migration: Double = 120
    }

    /// 알림 구독 한 벌 — 끊을 때 셋을 함께 정리한다.
    private struct Observation {
        let center: NotificationCenter
        let token: any NSObjectProtocol
        let continuation: AsyncStream<CloudSyncEvent>.Continuation
        let task: Task<Void, Never>
    }

    /// 계정을 확인하고, 초기 import 의 결론이나 제한 시간까지 기다린다. **한 번만** 기다린다.
    public func observeCloudKitSyncProgress() async {
        // ★ 계정을 조회하기 **전에** 구독을 시작한다. 이전 구현은 계정 조회가 끝난 뒤에야
        //   구독을 열어, 그 사이에 도착한 이벤트를 놓쳤다.
        guard let deadline = await beginInitialWait() else { return }
        // 설정 화면과 같은 조회를 쓴다 — 조회 실패를 "계정 없음" 으로 단정하지 않는 규칙이 한곳에 있다.
        @Dependency(\.cloudAccountStatus) var accountStatus
        do {
            // 계정 조회도 같은 제한 안에서 한다. 이전 구현은 이 호출이 제한 밖이라
            // 계정 조회가 오래 걸리면 기다린 시간이 집계되지 않았다.
            try await Task.withTimeout(seconds: deadline) { [weak self] in
                let availability = await accountStatus.availability()
                // ★ 결과를 보기 **전에** 취소를 확인한다. 조회 구현은 취소를 포함한 모든 오류를 `.unknown` 으로 바꾸므로,
                //   먼저 분기하면 조회 도중의 취소를 "계정 상태를 확인하지 못했다" 로 읽는다(시험에서 10번 중 10번).
                try Task.checkCancellation()
                switch availability {
                case .available:
                    break
                case .noAccount, .restricted:
                    throw InitialWaitError.accountUnavailable
                case .unknown, .checking:
                    throw InitialWaitError.accountCheckFailed
                }
                await self?.waitForInitialConclusion()
            }
        } catch {
            // 기다리던 호출이 취소됐으면 어떤 오류로 끝났든 상태를 바꾸지 않는다. 취소는 시간 초과 작업에도 함께 전해지고,
            // 어느 쪽 오류가 먼저 올라올지는 정해져 있지 않다.
            guard !Task.isCancelled else { return }
            await concludeInitialWait(after: error)
        }
    }

    /// 관찰을 설치하고 초기 대기 상태를 정한다 — **이벤트 반영(`receive`)과 같은 MainActor 에서, 한 번에.**
    ///
    /// 이전 구현은 이벤트 반영은 MainActor 에서, 상태 초기화(`.syncing`)는 그 밖에서 했다. 그래서 구독이 먼저 받은
    /// 결론을 초기화가 지우고, 오지 않을 결론을 기다리다 "시간이 걸리고 있어요" 로 끝날 수 있었다.
    /// - Returns: 기다릴 한도(초). 이미 대기를 시작했거나 결론이 나 있으면 nil — 결론을 되돌리지 않는다.
    @MainActor
    private func beginInitialWait() -> Double? {
        startObserving()
        guard !initialWaitStarted else { return nil }
        initialWaitStarted = true
        switch syncState {
        case .idle:
            syncState = .syncing
            return initialWaitLimit.normal
        case .migration:
            return initialWaitLimit.migration
        case .syncing, .stillWaiting:
            return initialWaitLimit.normal
        case .syncCompleted, .migrationCompleted, .migrationEndedWithoutImport, .failed, .storeUnavailable:
            // `storeUnavailable` 은 컨테이너를 만들 때 정해진다. 기다릴 CloudKit 도 조회할 계정도 없다.
            Log.debug("초기 대기 — 대기를 시작하기 전에 결론이 났다", "\(syncState)")
            return nil
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
        syncState = (syncState == .migration) ? Self.migrationOutcome(outcome) : outcome
    }

    /// 마이그레이션 모드의 결론 — 일반 모드의 결론을 **들어가지 않는** 결론으로 옮긴다. 순수 함수다 (테스트 계획 MIG-F1).
    ///
    /// 이전 구현은 마이그레이션 모드에서도 계정 없음 · 확인 실패 · import 실패 · 시간 초과를 일반 모드와 같은 상태로 보내,
    /// 시작 화면이 V1 전용 컨테이너를 쥔 채 필사 화면에 들어갔다.
    static func migrationOutcome(_ outcome: CloudSyncState) -> CloudSyncState {
        switch outcome {
        case .syncCompleted: .migrationCompleted
        case .failed(let reason): .migrationEndedWithoutImport(reason)
        case .stillWaiting: .migrationEndedWithoutImport(nil)
        case .idle, .syncing, .migration, .migrationCompleted, .migrationEndedWithoutImport, .storeUnavailable: outcome
        }
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

    /// CloudKit 이벤트 관찰을 **앱 수명 동안** 시작한다. 여러 번 불러도 한 번만 시작한다.
    ///
    /// - Important: 이전 구현은 초기 import 하나를 확인하면 관찰을 끝냈다. 그래서 시작 화면이 지난 뒤의
    ///              동기화 상태를 앱이 전혀 알지 못했다. 이제는 관찰을 끊지 않고 ``activity`` 를 계속 갱신한다.
    /// - Important: **돌아올 때 구독은 이미 걸려 있다.** 이전 구현은 Task 안에서 알림 시퀀스를 만들어, 그 Task 가
    ///              돌기 전에 게시된 이벤트를 놓쳤다. 구독은 여기서 동기로 걸고, 도착한 이벤트는 순서대로 쌓아 두었다가
    ///              MainActor 에서 반영한다 — 알림을 보낸 스레드에서 MainActor 를 기다리지 않는다.
    @MainActor
    public func startObserving() {
        guard observation == nil else { return }
        let source = eventSource
        let (events, continuation) = AsyncStream<CloudSyncEvent>.makeStream()
        let token = source.center.addObserver(forName: source.name, object: nil, queue: nil) { notification in
            guard let event = source.event(notification) else { return }
            continuation.yield(event)
        }
        let task = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                self.receive(event)
            }
        }
        observation = Observation(center: source.center, token: token, continuation: continuation, task: task)
    }

    deinit {
        guard let observation else { return }
        observation.center.removeObserver(observation.token)
        observation.continuation.finish()
        observation.task.cancel()
    }

    /// 관찰을 멈춘다. 앱이 살아 있는 동안은 부를 일이 없고, 테스트·해제 때만 쓴다.
    @MainActor
    public func stopObserving() {
        guard let observation else { return }
        observation.center.removeObserver(observation.token)
        observation.continuation.finish()
        observation.task.cancel()
        self.observation = nil
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
    ///
    /// **확인된 오류(`failed`)로 멈춘 뒤에도 import 가 성공하면 받은 것이다** — 결론을 `syncCompleted` 로 바꾼다(2026-09-21 후속 리뷰 2차).
    /// 초기 복원 화면은 오류에서 들어가지 않고 기다리므로(`LaunchWaitRule`), 바꾸지 않으면 실제로 필사를 받았는데도 오류 안내에 머물러
    /// "import 성공 후 진입" 을 지키지 못한다. 마이그레이션 결론 · 저장소를 쓸 수 없는 상태는 그대로 둔다 — 재실행 요구 · 막힘이다(MIG-F1).
    private func applyToInitialWait(_ event: CloudSyncEvent) {
        if case .failed = syncState, CloudSyncStateRule.isAwaitedImportSuccess(event) {
            Log.info("초기 대기 — 오류로 멈춘 뒤 import 가 성공했다. 받은 것으로 결론을 바꾼다", "\(syncState)")
            syncState = .syncCompleted
            return
        }
        guard syncState.isInProgress else { return }
        let outcome: CloudSyncState
        if CloudSyncStateRule.isAwaitedImportSuccess(event) {
            outcome = .syncCompleted
        } else if CloudSyncStateRule.isImportFailure(event) {
            outcome = .failed(.importFailed)
        } else {
            return
        }
        syncState = (syncState == .migration) ? Self.migrationOutcome(outcome) : outcome
    }

    /// 초기 대기가 끝날 때까지 기다린다. 판정은 관찰 Task 가 하고 여기서는 결론만 본다.
    private func waitForInitialConclusion() async {
        for await state in $syncState.values where !state.isInProgress {
            return
        }
    }

    /// CloudKit 알림에서 판정에 필요한 값만 남긴 `CloudSyncEvent` 를 꺼낸다.
    static func cloudKitEvent(from notification: Notification) -> CloudSyncEvent? {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return nil }
        Log.debug("cloudEvent", event.debugDescription)
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
