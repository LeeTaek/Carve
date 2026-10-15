//
//  AppCoordinatorSettingsLifecycleTesting.swift
//  CarveAppTest
//
//  설정을 「완료」 로 닫을 때 — 하위 화면(iCloud · 확인이 필요한 필기)의 구독은 코디네이터의 `ifLet` 이 끝내고, 화면은 사라질 때 보낼 것이 없다.
//  사라질 때 정리 액션을 보내면 SwiftUI 가 설정 상태를 nil 로 바꾼 **뒤에** 불러 `ifLet` 경고가 났다(2026-10-13 · 10-15 시뮬레이터).
//

import Domain
import Foundation
import SettingsFeature
import Testing

import ComposableArchitecture

// MARK: - 대역

/// 끝나지 않는 동기화 활동 — 효과가 취소될 때만 끝난다. 구독 · 끝남을 센다.
private final class HangingSyncActivity: CloudSyncActivityClient {
    let subscriptions = LockIsolated(0)
    let terminations = LockIsolated(0)
    private let continuations = LockIsolated<[AsyncStream<CloudSyncActivity>.Continuation]>([])

    func activities() -> AsyncStream<CloudSyncActivity> {
        let (stream, continuation) = AsyncStream<CloudSyncActivity>.makeStream()
        continuation.onTermination = { [terminations] _ in terminations.withValue { $0 += 1 } }
        continuations.withValue { $0.append(continuation) }
        subscriptions.withValue { $0 += 1 }
        return stream
    }
}

/// 끝나지 않는 편집 환경 알림 — 효과가 취소될 때만 끝난다. 구독 · 끝남을 센다.
private final class HangingEditEnvironment: DrawingEditEnvironmentClient {
    let environment: DrawingEditEnvironment
    let subscriptions = LockIsolated(0)
    let terminations = LockIsolated(0)
    private let continuations = LockIsolated<[AsyncStream<Void>.Continuation]>([])

    init(_ environment: DrawingEditEnvironment) {
        self.environment = environment
    }

    func current() async -> DrawingEditEnvironment { environment }
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool { environment.serverWork == token }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { [terminations] _ in terminations.withValue { $0 += 1 } }
        continuations.withValue { $0.append(continuation) }
        subscriptions.withValue { $0 += 1 }
        return stream
    }
}

/// 조건이 참이 될 때까지 효과에 양보한다. 시험이 멈추지 않게 2초를 넘기면 그만두고 false.
@MainActor
private func yieldUntil(_ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !condition() {
        guard clock.now < deadline else { return false }
        await Task.yield()
    }
    return true
}

@Suite("코디네이터 — 설정을 닫을 때 하위 화면 구독 정리")
@MainActor
struct AppCoordinatorSettingsLifecycleTesting {
    @Test("「완료」 로 설정을 닫으면 iCloud 화면의 동기화 활동 · 연결 관찰 구독이 그 자리에서 끝난다")
    func closingSettingsEndsICloudSubscriptions() async {
        let activity = HangingSyncActivity()
        let environment = HangingEditEnvironment(.ownedForTesting)
        // 보류 중이어야 iCloud 화면이 연결 관찰(편집 환경 구독)까지 건다.
        let store = makeCoordinatorStore(
            CoordinatorFixture.writing(settings: .initialState(path: .iCloud(.initialState))),
            hold: LegacySeparationHold(reason: .ownershipUnverified)
        )
        store.dependencies.cloudSyncActivity = activity
        store.dependencies.drawingEditEnvironment = environment

        // Given: 설정의 iCloud 화면이 나타나 두 구독을 건다.
        await store.send(.settings(.presented(.path(.presented(.iCloud(.view(.onAppear)))))))
        #expect(await yieldUntil { activity.subscriptions.value == 1 && environment.subscriptions.value == 1 })

        // When: 「완료」 로 설정을 닫는다.
        await store.send(.settings(.presented(.view(.backToCarve)))) {
            $0.settings = nil
        }

        // Then: iCloud 화면이 아무것도 보내지 않아도 두 구독이 끝났다.
        await store.finish()
        #expect(activity.terminations.value == 1)
        #expect(environment.terminations.value == 1)
    }

    @Test("「완료」 로 설정을 닫으면 확인이 필요한 필기 화면의 편집 환경 구독이 그 자리에서 끝난다")
    func closingSettingsEndsDraftRecoverySubscription() async {
        let environment = HangingEditEnvironment(.ownedForTesting)
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: .initialState(path: .draftRecovery(.initialState))))
        store.dependencies.drawingEditEnvironment = environment

        // Given: 설정의 확인이 필요한 필기 화면이 나타나 편집 환경을 구독한다(보존 영역이 없어 목록은 곧바로 실패로 끝난다).
        await store.send(.settings(.presented(.path(.presented(.draftRecovery(.view(.onAppear)))))))
        #expect(await yieldUntil { environment.subscriptions.value == 1 })

        // When: 「완료」 로 설정을 닫는다.
        await store.send(.settings(.presented(.view(.backToCarve)))) {
            $0.settings = nil
        }

        // Then: 화면이 아무것도 보내지 않아도 구독이 끝났다.
        await store.finish()
        #expect(environment.terminations.value == 1)
    }
}
