//
//  RemoveAdsFeatureTesting.swift
//  SettingsFeatureTest
//
//  Created by Claude on 9/14/26.
//

@testable import SettingsFeature
import ClientInterfaces
import Foundation
import Testing

import ComposableArchitecture

private let stubProduct = RemoveAdsProduct(displayName: "광고 제거", displayPrice: "₩4,400")

/// 광고 제거 구매 · 복원(시안 K4). 구매 여부는 공유 권한 하나로만 바뀐다.
@Suite("광고 제거 구매")
@MainActor
struct RemoveAdsFeatureTesting {
    @Test("화면이 나타나면 구매 여부와 가격을 받는다")
    func appearLoadsEntitlementAndPrice() async throws {
        let suite = "RemoveAdsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = StubPurchaseClient(isAdFree: adFreeShared(in: defaults))
        let store = makeStore(client: client, appStorage: defaults)

        await store.send(.view(.onAppear)) {
            $0.isLoadingProduct = true
        }
        await store.receive(\.adFreeChanged)
        await store.receive(\.productResponse) {
            $0.isLoadingProduct = false
            $0.product = stubProduct
        }
        await store.send(.view(.onDisappear))
    }

    @Test("구매가 끝나면 공유 권한이 바뀌어 구매함으로 보인다")
    func purchaseMarksAdFreeThroughSharedEntitlement() async throws {
        let suite = "RemoveAdsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = StubPurchaseClient(isAdFree: adFreeShared(in: defaults))
        let store = makeStore(client: client, appStorage: defaults)

        await store.send(.view(.onAppear)) {
            $0.isLoadingProduct = true
        }
        await store.receive(\.adFreeChanged)
        await store.receive(\.productResponse) {
            $0.isLoadingProduct = false
            $0.product = stubProduct
        }

        await store.send(.view(.purchaseTapped)) {
            $0.inProgress = .purchase
        }
        await store.receive(\.adFreeChanged) {
            $0.isAdFree = true
        }
        await store.receive(\.purchaseResponse) {
            $0.inProgress = nil
        }
        await store.send(.view(.onDisappear))
    }

    @Test("보호자 승인을 기다리면 안내만 띄우고 구매함으로 바꾸지 않는다")
    func pendingPurchaseShowsNotice() async {
        let client = StubPurchaseClient(purchase: .success(.pending))
        let store = makeStore(client: client)

        await store.send(.view(.purchaseTapped)) {
            $0.inProgress = .purchase
        }
        await store.receive(\.purchaseResponse) {
            $0.inProgress = nil
            $0.notice = .pending
        }
        #expect(!store.state.isAdFree)
    }

    @Test("결제 창을 닫으면 아무 안내도 하지 않는다")
    func cancelledPurchaseIsQuiet() async {
        let client = StubPurchaseClient(purchase: .success(.cancelled))
        let store = makeStore(client: client)

        await store.send(.view(.purchaseTapped)) {
            $0.inProgress = .purchase
        }
        await store.receive(\.purchaseResponse) {
            $0.inProgress = nil
        }
    }

    @Test("상품을 찾지 못하면 지금은 구매할 수 없다고, 그 밖의 실패는 다시 시도하라고 안내한다")
    func purchaseFailuresShowNotice() async {
        let unavailable = makeStore(client: StubPurchaseClient(purchase: .failure(.productNotFound)))
        await unavailable.send(.view(.purchaseTapped)) {
            $0.inProgress = .purchase
        }
        await unavailable.receive(\.purchaseResponse) {
            $0.inProgress = nil
            $0.notice = .productUnavailable
        }

        let failed = makeStore(client: StubPurchaseClient(purchase: .failure(.verificationFailed)))
        await failed.send(.view(.purchaseTapped)) {
            $0.inProgress = .purchase
        }
        await failed.receive(\.purchaseResponse) {
            $0.inProgress = nil
            $0.notice = .purchaseFailed
        }
    }

    @Test("복원할 구매 내역이 없으면 알려 준다")
    func restoreWithoutPurchaseShowsNotice() async {
        let client = StubPurchaseClient(restore: .success(.nothingToRestore))
        let store = makeStore(client: client)

        await store.send(.view(.restoreTapped)) {
            $0.inProgress = .restore
        }
        await store.receive(\.restoreResponse) {
            $0.inProgress = nil
            $0.notice = .nothingToRestore
        }
    }

    @Test("복원에 성공하면 공유 권한이 바뀌어 구매함으로 보이고, 이전 안내는 지운다")
    func restoreMarksAdFree() async throws {
        let suite = "RemoveAdsFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = StubPurchaseClient(isAdFree: adFreeShared(in: defaults))
        var state = RemoveAdsFeature.State()
        state.product = stubProduct
        state.notice = .nothingToRestore
        let store = makeStore(initialState: state, client: client, appStorage: defaults)

        await store.send(.view(.onAppear))
        await store.receive(\.adFreeChanged)

        await store.send(.view(.restoreTapped)) {
            $0.inProgress = .restore
            $0.notice = nil
        }
        await store.receive(\.adFreeChanged) {
            $0.isAdFree = true
        }
        await store.receive(\.restoreResponse) {
            $0.inProgress = nil
        }
        await store.send(.view(.onDisappear))
    }

    @Test("요청이 진행 중이면 구매 · 복원을 다시 받지 않고, 이미 샀으면 구매를 받지 않는다")
    func ignoresTapsWhileBusyOrAdFree() async {
        let client = StubPurchaseClient()

        var busy = RemoveAdsFeature.State()
        busy.inProgress = .purchase
        let busyStore = makeStore(initialState: busy, client: client)
        await busyStore.send(.view(.purchaseTapped))
        await busyStore.send(.view(.restoreTapped))

        var adFree = RemoveAdsFeature.State()
        adFree.isAdFree = true
        let adFreeStore = makeStore(initialState: adFree, client: client)
        await adFreeStore.send(.view(.purchaseTapped))

        #expect(client.purchaseCount == 0)
        #expect(client.restoreCount == 0)
    }

    /// 광고 제거 여부는 테스트마다 따로 둔다 — 기본 저장소를 함께 쓰면 다른 테스트에 권한이 샌다.
    private func adFreeShared(in defaults: UserDefaults) -> Shared<Bool> {
        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            Shared<Bool>(.isAdFree)
        }
    }

    private func makeStore(
        initialState: RemoveAdsFeature.State = RemoveAdsFeature.State(),
        client: StubPurchaseClient,
        appStorage: UserDefaults? = nil
    ) -> TestStoreOf<RemoveAdsFeature> {
        TestStore(initialState: initialState) {
            RemoveAdsFeature()
        } withDependencies: {
            $0.purchaseClient = client
            if let appStorage {
                $0.defaultAppStorage = appStorage
            }
        }
    }
}

/// 정해 둔 결과를 돌려주는 대역. 구매 · 복원이 성공하면 실제 클라이언트처럼 공유 권한에 쓴다.
@MainActor
private final class StubPurchaseClient: PurchaseClient {
    private let product: Result<RemoveAdsProduct, PurchaseClientError>
    private let purchase: Result<PurchaseOutcome, PurchaseClientError>
    private let restore: Result<RestoreOutcome, PurchaseClientError>
    private let isAdFree: Shared<Bool>?
    private(set) var purchaseCount = 0
    private(set) var restoreCount = 0

    init(
        product: Result<RemoveAdsProduct, PurchaseClientError> = .success(stubProduct),
        purchase: Result<PurchaseOutcome, PurchaseClientError> = .success(.purchased),
        restore: Result<RestoreOutcome, PurchaseClientError> = .success(.restored),
        isAdFree: Shared<Bool>? = nil
    ) {
        self.product = product
        self.purchase = purchase
        self.restore = restore
        self.isAdFree = isAdFree
    }

    func removeAdsProduct() async throws(PurchaseClientError) -> RemoveAdsProduct {
        try product.get()
    }

    func purchaseRemoveAds() async throws(PurchaseClientError) -> PurchaseOutcome {
        purchaseCount += 1
        let outcome = try purchase.get()
        if outcome == .purchased {
            isAdFree?.withLock { $0 = true }
        }
        return outcome
    }

    func restorePurchases() async throws(PurchaseClientError) -> RestoreOutcome {
        restoreCount += 1
        let outcome = try restore.get()
        if outcome == .restored {
            isAdFree?.withLock { $0 = true }
        }
        return outcome
    }
}
