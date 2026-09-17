//
//  CloudInitialWaitTesting.swift
//  DomainTest
//
//  시작 화면의 초기 대기가 **왜 끝났는지** (리뷰 P2-5).
//
//  이전 구현은 계정 조회가 던진 오류와 취소까지 한 `catch` 에서 "시간이 걸리고 있어요"(`stillWaiting`)로 보냈고,
//  관찰이 이미 낸 결론도 확인하지 않고 덮었다. 판정 함수만이 아니라 `observeCloudKitSyncProgress()` 를 실제로 돌린다.
//

import CarveToolkit
@testable import Domain
import Foundation
import Testing

import Dependencies

/// 계정 조회를 `release()` 까지 붙잡는다 — 조회가 끝나기 전에 관찰이 결론을 내거나 대기가 취소되는 순서를 만든다.
private final class HeldAccountStatus: CloudAccountStatusClient, @unchecked Sendable {
    private let result: CloudAccountAvailability
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(_ result: CloudAccountAvailability) {
        self.result = result
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func availability() async -> CloudAccountAvailability {
        for await _ in stream { break }
        return result
    }

    func release() {
        continuation.yield()
        continuation.finish()
    }
}

/// 조회하는 도중 기다리던 쪽을 취소하고 `.unknown` 을 돌려준다.
///
/// 실제 구현(`CloudKitAccountStatusClient`)은 조회가 던진 오류를 전부 `.unknown` 으로 바꾸므로, 조회 중에 취소되면
/// 취소 오류도 `.unknown` 으로 돌아올 수 있다. 그 결과를 "계정 확인 실패" 로 읽으면 안 된다.
private final class CancellingAccountStatus: CloudAccountStatusClient, @unchecked Sendable {
    private let lock = NSLock()
    private var target: Task<Void, Never>?

    func cancelDuringCheck(_ task: Task<Void, Never>) {
        lock.lock()
        target = task
        lock.unlock()
    }

    func availability() async -> CloudAccountAvailability {
        lock.lock()
        let task = target
        lock.unlock()
        task?.cancel()
        return .unknown
    }
}

@Suite("시작 화면 초기 대기 — 끝난 이유를 가른다")
@MainActor
struct CloudInitialWaitTesting {
    private let importSucceeded = CloudSyncEvent(kind: .cloudImport, ended: true, succeeded: true)

    private func makeContainer(limit: Double) -> PersistentCloudKitContainer {
        let container = PersistentCloudKitContainer()
        container.initialWaitLimit = .init(normal: limit, migration: limit)
        return container
    }

    private func observe(_ container: PersistentCloudKitContainer, account: any CloudAccountStatusClient) async {
        await withDependencies {
            $0.cloudAccountStatus = account
        } operation: {
            await container.observeCloudKitSyncProgress()
        }
        container.stopObserving()
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
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

    @Test("계정은 쓸 수 있는데 제한 시간 안에 import 결론이 없으면 기다리는 중이다 — 실패가 아니다")
    func timeoutIsStillWaiting() async {
        let container = makeContainer(limit: 0.2)
        await observe(container, account: StubCloudAccountStatusClient(.available))
        #expect(container.syncState == .stillWaiting)
    }

    @Test("계정 상태를 확인하지 못하면 확인 실패다 — '시간이 걸리고 있어요' 로도, '계정 없음' 으로도 두지 않는다")
    func accountCheckFailureIsItsOwnFailure() async {
        let container = makeContainer(limit: 5)
        await observe(container, account: StubCloudAccountStatusClient(.unknown))
        #expect(container.syncState == .failed(.accountCheckFailed))
    }

    @Test("계정이 없거나 제한됐으면 계정 문제다", arguments: [CloudAccountAvailability.noAccount, .restricted])
    func missingAccountIsAccountUnavailable(_ availability: CloudAccountAvailability) async {
        let container = makeContainer(limit: 5)
        await observe(container, account: StubCloudAccountStatusClient(availability))
        #expect(container.syncState == .failed(.accountUnavailable))
    }

    @Test("대기가 취소되면 상태를 바꾸지 않는다 — 기다리던 화면이 사라졌을 뿐이다")
    func cancellationChangesNothing() async throws {
        let container = makeContainer(limit: 30)
        let account = HeldAccountStatus(.available)
        let waiting = Task { await observe(container, account: account) }
        try await waitUntil { container.syncState == .syncing }

        waiting.cancel()
        account.release()
        await waiting.value

        // ★ 이전 구현은 취소도 "시간이 걸리고 있어요" 로 바꿨다.
        #expect(container.syncState == .syncing)
    }

    /// 취소와 시간 초과 작업의 오류 중 무엇이 먼저 전달되는지는 실행마다 다를 수 있어 여러 번 본다.
    @Test("계정 조회 도중 취소돼 조회가 .unknown 으로 끝나도 상태를 바꾸지 않는다 — 확인 실패로 보이지 않는다")
    func cancellationDuringAccountCheckIsNotCheckFailure() async {
        for _ in 0..<10 {
            let container = makeContainer(limit: 30)
            let account = CancellingAccountStatus()
            // 대기는 MainActor 를 거쳐 시작하므로, 이 줄이 조회보다 먼저 실행된다.
            let waiting = Task { await observe(container, account: account) }
            account.cancelDuringCheck(waiting)
            await waiting.value

            #expect(container.syncState == .syncing)
        }
    }

    @Test("관찰이 먼저 결론을 냈으면 늦게 끝난 계정 조회가 그 결론을 덮지 않는다")
    func lateAccountResultKeepsConclusion() async throws {
        let container = makeContainer(limit: 30)
        let account = HeldAccountStatus(.noAccount)
        let waiting = Task { await observe(container, account: account) }
        try await waitUntil { container.syncState == .syncing }

        container.receive(importSucceeded)
        #expect(container.syncState == .syncCompleted)

        account.release()
        await waiting.value
        // ★ 이전 구현은 여기서 "iCloud 계정을 확인해 주세요" 로 덮었다.
        #expect(container.syncState == .syncCompleted)
    }

    @Test("제한 시간이 지난 뒤 도착한 import 성공은 반영한다 — '기다리는 중' 은 결론이 아니다")
    func importAfterTimeoutIsStillApplied() async {
        let container = makeContainer(limit: 0.2)
        await observe(container, account: StubCloudAccountStatusClient(.available))
        #expect(container.syncState == .stillWaiting)

        container.receive(importSucceeded)
        #expect(container.syncState == .syncCompleted)
    }

    @Test("끝난 이유의 뜻 — 시간 초과만 기다리는 중이고, 취소는 바꾸지 않으며, 모르는 오류는 실패다")
    func outcomeTable() {
        typealias Container = PersistentCloudKitContainer
        #expect(Container.initialWaitOutcome(after: TaskTimeoutError(seconds: 20)) == .stillWaiting)
        #expect(Container.initialWaitOutcome(after: CancellationError()) == nil)
        #expect(Container.initialWaitOutcome(after: URLError(.notConnectedToInternet)) == .failed(.unknown))
    }
}
