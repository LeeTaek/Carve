//
//  CloudObservationOrderTesting.swift
//  DomainTest
//
//  관찰 설치 · 상태 초기화 · 이벤트 반영의 **실행 순서** (리뷰 P2-4).
//
//  이전 구현은 `startObserving()` 이 Task 를 만들고 곧바로 돌아와, 그 Task 가 알림 시퀀스를 만들기 전에 게시된 이벤트를
//  놓칠 수 있었다. 초기 대기는 이벤트 반영과 다른 격리에서 상태를 `.syncing` 으로 되돌려, 이미 관찰한 결론을 지웠다.
//  판정 함수가 아니라 알림을 실제로 게시해 순서를 만든다.
//

@testable import Domain
import Foundation
import Testing

import Dependencies

/// 계정 조회 횟수를 센다. 조회는 `release()` 까지 붙잡는다.
private final class CountingAccountStatus: CloudAccountStatusClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func availability() async -> CloudAccountAvailability {
        lock.lock()
        count += 1
        lock.unlock()
        for await _ in stream { break }
        return .available
    }

    func release() {
        continuation.yield()
        continuation.finish()
    }
}

@Suite("동기화 관찰 — 설치 · 초기화 · 반영의 순서")
@MainActor
struct CloudObservationOrderTesting {
    private static let name = Notification.Name("CloudObservationOrderTesting.event")
    private let importSucceeded = CloudSyncEvent(kind: .cloudImport, ended: true, succeeded: true)

    private func makeContainer(
        center: NotificationCenter = NotificationCenter(),
        limit: Double = 0.3,
        migrationLimit: Double? = nil
    ) -> PersistentCloudKitContainer {
        let container = PersistentCloudKitContainer()
        container.initialWaitLimit = .init(normal: limit, migration: migrationLimit ?? limit)
        container.eventSource = .init(center: center, name: Self.name, event: { $0.userInfo?["event"] as? CloudSyncEvent })
        return container
    }

    private func post(_ event: CloudSyncEvent, on center: NotificationCenter) {
        center.post(name: Self.name, object: nil, userInfo: ["event": event])
    }

    private func observe(_ container: PersistentCloudKitContainer) async {
        await withDependencies {
            $0.cloudAccountStatus = StubCloudAccountStatusClient(.available)
        } operation: {
            await container.observeCloudKitSyncProgress()
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("구독은 startObserving 이 돌아올 때 이미 걸려 있다 — 바로 뒤에 게시된 이벤트를 놓치지 않는다")
    func subscriptionIsReadyWhenStartReturns() async throws {
        // 한 번은 운 좋게 잡힐 수 있어 여러 번 본다.
        for _ in 0..<10 {
            let center = NotificationCenter()
            let container = makeContainer(center: center)
            container.startObserving()
            post(importSucceeded, on: center)

            try await waitUntil(timeout: .milliseconds(500)) { container.activity.lastImportSuccess != nil }
            container.stopObserving()
        }
    }

    @Test("대기를 시작하기 전에 관찰이 낸 결론을 초기화가 덮지 않는다")
    func conclusionObservedBeforeWaitSurvives() async throws {
        let center = NotificationCenter()
        let container = makeContainer(center: center)
        container.startObserving()
        // 구독 준비와 섞이지 않게 잠시 뒤에 게시한다 — 이 테스트는 초기화 순서만 본다.
        try await Task.sleep(for: .milliseconds(100))
        post(importSucceeded, on: center)
        try await waitUntil { container.syncState == .syncCompleted }

        await observe(container)

        // ★ 이전 구현은 여기서 `.syncing` 으로 되돌린 뒤 오지 않을 결론을 기다리다 "시간이 걸리고 있어요" 로 끝났다.
        #expect(container.syncState == .syncCompleted)
        container.stopObserving()
    }

    @Test("대기하는 중에 다시 불러도 두 번째 대기를 시작하지 않는다 — 계정 조회와 제한 시간은 한 벌이다")
    func concurrentCallDoesNotStartSecondWait() async throws {
        let container = makeContainer(limit: 30)
        let account = CountingAccountStatus()
        let first = Task {
            await withDependencies { $0.cloudAccountStatus = account } operation: {
                await container.observeCloudKitSyncProgress()
            }
        }
        try await waitUntil { account.calls == 1 }

        // 두 번째 호출은 곧바로 돌아와야 한다 — 기다리면 이 줄에서 멈춘다.
        await withDependencies { $0.cloudAccountStatus = account } operation: {
            await container.observeCloudKitSyncProgress()
        }
        #expect(account.calls == 1)
        #expect(container.syncState == .syncing)

        first.cancel()
        account.release()
        await first.value
        container.stopObserving()
    }

    @Test("대기가 끝난 뒤 다시 불러도 결론을 되돌리지 않는다")
    func secondWaitDoesNotResetConclusion() async {
        let container = makeContainer(limit: 0.2)
        await observe(container)
        #expect(container.syncState == .stillWaiting)
        container.receive(importSucceeded)
        #expect(container.syncState == .syncCompleted)

        await observe(container)

        #expect(container.syncState == .syncCompleted)
        container.stopObserving()
    }

    @Test("마이그레이션 중이면 마이그레이션 한도로 기다리고 상태를 syncing 으로 바꾸지 않는다")
    func migrationWaitKeepsItsStateAndLimit() async throws {
        let container = makeContainer(limit: 0.1, migrationLimit: 1.0)
        container.syncState = .migration
        let waiting = Task { await observe(container) }

        // 일반 한도(0.1초)는 지났지만 마이그레이션 한도(1초)는 아직이다.
        try await Task.sleep(for: .milliseconds(400))
        #expect(container.syncState == .migration)

        await waiting.value
        #expect(container.syncState == .stillWaiting)
        container.stopObserving()
    }
}
