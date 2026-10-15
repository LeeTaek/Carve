//
//  SettingsDetailLifecycleTesting.swift
//  SettingsFeatureTest
//
//  설정 하위 화면(iCloud · 확인이 필요한 필기 · 광고 제거)을 떠날 때 — 구독은 부모의 `ifLet` 이 끝내고, 화면은 사라질 때 보낼 것이 없다.
//  사라질 때 정리 액션을 보내면 SwiftUI 가 경로를 바꾼 **뒤에** 불러 `ifCaseLet` 경고가 났다(2026-10-13 · 10-15 시뮬레이터).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

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

/// 남겨 둔 필기가 없는 보존 영역.
private struct EmptyDraftReader: VerseDraftRecoveryReading {
    func draftBuckets() async throws -> [AccountScope] { [] }
    func draftSummary(in scope: AccountScope) async throws -> DraftBucketSummary {
        DraftBucketSummary(scope: scope, draftCount: 0, draftBytes: 0, unreadableCount: 0, unreadableBytes: 0, chapters: [])
    }
    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] { [] }
    func unreadableDraftFiles(in scope: AccountScope) async throws -> [URL] { [] }
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

/// 이 파일이 막는 것: 사라질 때의 정리 액션(onDisappear)을 지운 뒤 구독 정리까지 빠지는 것 — 떠나는 순간 부모의 `ifLet` 이 끝내야 한다.
/// 그 액션은 설정이 경로를 바꾼 뒤에 와서 `ifCaseLet` 경고를 내고 정리째 버려졌다 — 그래서 지웠다(룰북 navigation.md 「화면이 사라질 때」).
///
/// 효과가 보내는 액션의 차례가 정해진 시험은 망라 모드다 — 떠난 뒤 `finish()` 가 끝나지 않은 효과를 실패로 알린다.
@Suite("설정 — 하위 화면을 떠날 때 구독 정리")
@MainActor
struct SettingsDetailLifecycleTesting {
    private static let hold = LegacySeparationHold(reason: .ownershipUnverified)

    @Test("iCloud 화면에서 다른 항목으로 옮기면 동기화 활동 · 연결 관찰 구독이 그 자리에서 끝난다")
    func leavingICloudEndsSubscriptions() async {
        let activity = HangingSyncActivity()
        let environment = HangingEditEnvironment(.ownedForTesting)
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .iCloud(.initialState))) {
            SettingsFeature()
        } withDependencies: {
            $0.cloudAccountStatus = StubCloudAccountStatusClient(.available)
            $0.cloudSyncActivity = activity
            // 보류 중이어야 연결 관찰(편집 환경 구독)까지 건다.
            $0.legacySeparationHoldState = LegacySeparationHoldState(hold: Self.hold)
            $0.drawingEditEnvironment = environment
        }
        // 계정 조회와 연결 관찰이 각자 액션을 보내 도착 차례가 정해지지 않는다 — 구독은 대역의 수로 본다.
        store.exhaustivity = .off

        // Given: iCloud 화면이 나타나 계정을 조회하고 두 구독을 건다.
        await store.send(.path(.presented(.iCloud(.view(.onAppear)))))
        #expect(await yieldUntil { activity.subscriptions.value == 1 && environment.subscriptions.value == 1 })

        // When: 사이드바에서 화면 모드를 고른다.
        await store.send(.selectSidebarItem(.appearance)) {
            $0.path = .appearance(.initialState)
        }

        // Then: iCloud 화면이 아무것도 보내지 않아도 두 구독이 끝났다.
        await store.finish()
        #expect(activity.terminations.value == 1)
        #expect(environment.terminations.value == 1)
    }

    @Test("확인이 필요한 필기 화면에서 다른 항목으로 옮기면 편집 환경 구독이 그 자리에서 끝난다")
    func leavingDraftRecoveryEndsSubscription() async {
        let environment = HangingEditEnvironment(.ownedForTesting)
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .draftRecovery(.initialState))) {
            SettingsFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = EmptyDraftReader()
            $0.drawingEditEnvironment = environment
        }
        var screen = DraftRecoveryFeature.State.initialState

        // Given: 화면이 나타나 목록을 읽고 편집 환경을 구독한다.
        await store.send(.path(.presented(.draftRecovery(.view(.onAppear))))) {
            screen.loadSequence = 1
            screen.isLoading = true
            $0.path = .draftRecovery(screen)
        }
        await store.receive(\.path.draftRecovery.loaded) {
            screen.isLoading = false
            screen.stamp = DraftRecoveryFeature.Stamp(.ownedForTesting)
            $0.path = .draftRecovery(screen)
        }
        #expect(await yieldUntil { environment.subscriptions.value == 1 })

        // When: 사이드바에서 필사 백업을 고른다.
        await store.send(.selectSidebarItem(.backup)) {
            $0.path = .backup(.initialState)
        }

        // Then: 화면이 아무것도 보내지 않아도 구독이 끝났다.
        await store.finish()
        #expect(environment.terminations.value == 1)
    }

    @Test("광고 제거 화면에서 다른 항목으로 옮기면 구매 여부 구독이 그 자리에서 끝난다")
    func leavingRemoveAdsEndsSubscription() async {
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .removeAds(.initialState))) {
            SettingsFeature()
        }
        var screen = RemoveAdsFeature.State.initialState

        // Given: 화면이 나타나 구매 여부를 구독하고 상품을 받는다(시험 기본 구매 클라이언트는 상품을 찾지 못한다).
        await store.send(.path(.presented(.removeAds(.view(.onAppear))))) {
            screen.isLoadingProduct = true
            $0.path = .removeAds(screen)
        }
        await store.receive(\.path.removeAds.adFreeChanged)
        await store.receive(\.path.removeAds.productResponse) {
            screen.isLoadingProduct = false
            $0.path = .removeAds(screen)
        }

        // When: 사이드바에서 화면 모드를 고른다.
        await store.send(.selectSidebarItem(.appearance)) {
            $0.path = .appearance(.initialState)
        }

        // Then: 구독(끝나지 않는 공유 값 publisher)이 남아 있으면 finish 가 실패한다.
        await store.finish()
    }
}
