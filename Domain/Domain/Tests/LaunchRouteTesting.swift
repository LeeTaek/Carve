//
//  LaunchRouteTesting.swift
//  DomainTest
//
//  MIG-F1 — 시작 화면이 필사 화면에 들어갈지 정하는 판정 (정책 §3 표 4행).
//
//  이전 구현은 마이그레이션 모드(V1 전용 컨테이너)에서도 계정 없음 · 확인 실패 · import 실패 · 시간 초과를 일반 모드와 같은
//  `failed` · `stillWaiting` 으로 보내, 1.5초 뒤 필사 화면에 들어갔다. 판정 표만이 아니라 `observeCloudKitSyncProgress()` 를
//  실제로 돌려 끝난 상태가 들어가는 상태가 아닌지 본다. 저장소 판별은 `LocalStoreLoadFailureTesting` 이 본다.
//

@testable import Domain
import Foundation
import Testing

import Dependencies

/// 계정 조회 횟수를 센다. 조회하면 곧바로 `.available` 을 돌려준다.
private final class CountingAccountStatusClient: CloudAccountStatusClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func availability() async -> CloudAccountAvailability {
        lock.lock()
        count += 1
        lock.unlock()
        return .available
    }
}

@Suite("MIG-F1 — 시작 화면 진입 판정")
@MainActor
struct LaunchRouteTesting {
    private typealias State = PersistentCloudKitContainer.CloudSyncState
    private static let name = Notification.Name("LaunchRouteTesting.event")

    private func makeContainer(_ state: State, limit: Double = 5) -> PersistentCloudKitContainer {
        let container = PersistentCloudKitContainer()
        container.initialWaitLimit = .init(normal: limit, migration: limit)
        container.eventSource = .init(center: NotificationCenter(), name: Self.name, event: { _ in nil })
        container.syncState = state
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

    @Test("상태마다 시작 화면이 할 일 — 마이그레이션 모드의 결론과 저장소를 쓸 수 없는 상태는 들어가지 않는다")
    func routeTable() {
        #expect(State.idle.launchRoute == .stay)
        #expect(State.syncing.launchRoute == .stay)
        #expect(State.migration.launchRoute == .stay)

        #expect(State.syncCompleted.launchRoute == .enterWriting)
        #expect(State.stillWaiting.launchRoute == .enterWriting)
        #expect(State.failed(.accountUnavailable).launchRoute == .enterWriting)
        #expect(State.failed(.importFailed).launchRoute == .enterWriting)

        #expect(State.migrationCompleted.launchRoute == .restartRequired)
        #expect(State.migrationEndedWithoutImport(nil).launchRoute == .restartRequired)
        #expect(State.migrationEndedWithoutImport(.accountUnavailable).launchRoute == .restartRequired)

        #expect(State.storeUnavailable(.unknownVersion).launchRoute == .blocked(.unknownVersion))
        #expect(State.storeUnavailable(.openFailed).launchRoute == .blocked(.openFailed))
        #expect(State.storeUnavailable(.unreadable).launchRoute == .blocked(.unreadable))
    }

    @Test(
        "마이그레이션 모드에서 계정 문제로 대기가 끝나도 들어가지 않는다",
        arguments: zip(
            [CloudAccountAvailability.noAccount, .restricted, .unknown],
            [CloudSyncFailure.accountUnavailable, .accountUnavailable, .accountCheckFailed]
        )
    )
    func migrationAccountProblemsRequireRestart(_ availability: CloudAccountAvailability, _ reason: CloudSyncFailure) async {
        let container = makeContainer(.migration)
        await observe(container, account: StubCloudAccountStatusClient(availability))

        // ★ 이전 구현은 여기서 `failed(reason)` 이 돼 필사 화면에 들어갔다.
        #expect(container.syncState == .migrationEndedWithoutImport(reason))
        #expect(container.syncState.launchRoute == .restartRequired)
    }

    @Test("마이그레이션 모드에서 제한 시간이 지나도 '기다리는 중' 으로 들어가지 않는다")
    func migrationTimeoutRequiresRestart() async {
        let container = makeContainer(.migration, limit: 0.2)
        await observe(container, account: StubCloudAccountStatusClient(.available))

        #expect(container.syncState == .migrationEndedWithoutImport(nil))
        #expect(container.syncState.launchRoute == .restartRequired)
    }

    @Test("마이그레이션 모드의 import 는 성공이면 완료, 실패면 재실행 요구다 — 어느 쪽도 들어가지 않는다")
    func migrationImportConclusions() {
        let succeeded = makeContainer(.migration)
        succeeded.receive(CloudSyncEvent(kind: .cloudImport, ended: true, succeeded: true))
        #expect(succeeded.syncState == .migrationCompleted)

        let failed = makeContainer(.migration)
        failed.receive(CloudSyncEvent(kind: .cloudImport, ended: true, succeeded: false))
        #expect(failed.syncState == .migrationEndedWithoutImport(.importFailed))

        #expect([succeeded.syncState, failed.syncState].allSatisfy { $0.launchRoute == .restartRequired })
    }

    @Test("저장소를 쓸 수 없으면 계정을 조회하지도 CloudKit 을 기다리지도 않고, 늦게 온 이벤트에도 막힌 채 남는다")
    func unavailableStoreSkipsWaitAndStaysBlocked() async {
        // 기다렸다면 30초가 걸린다.
        let container = makeContainer(.storeUnavailable(.unknownVersion), limit: 30)
        let account = CountingAccountStatusClient()
        await observe(container, account: account)

        #expect(account.calls == 0)
        container.receive(CloudSyncEvent(kind: .cloudImport, ended: true, succeeded: true))
        #expect(container.syncState == .storeUnavailable(.unknownVersion))
        #expect(container.syncState.launchRoute == .blocked(.unknownVersion))
    }

    @Test("마이그레이션 모드의 결론 표 — 일반 모드의 결론을 들어가지 않는 결론으로 옮긴다")
    func migrationOutcomeTable() {
        typealias Container = PersistentCloudKitContainer
        #expect(Container.migrationOutcome(.syncCompleted) == .migrationCompleted)
        #expect(Container.migrationOutcome(.stillWaiting) == .migrationEndedWithoutImport(nil))
        #expect(Container.migrationOutcome(.failed(.unknown)) == .migrationEndedWithoutImport(.unknown))
        // 결론이 아닌 상태는 바꾸지 않는다.
        #expect(Container.migrationOutcome(.migration) == .migration)
    }
}
