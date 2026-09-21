//
//  StoreKitPurchaseClient.swift
//  CarveApp
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import StoreKit
import ClientInterfaces

import ComposableArchitecture

/// StoreKit 2 기반 광고 제거 구매(비소모성 · 가족 공유 끔).
///
/// - 권한 판정의 기준은 StoreKit 이다. 판정 결과를 `@Shared(.isAdFree)` 에 쓰는 곳은 여기 하나뿐이다.
/// - `Transaction.currentEntitlements` 는 기기에 저장된 서명 거래를 읽으므로 오프라인에서도 판정된다.
/// - 환불 · 다른 기기에서 한 구매 · 보호자 승인은 `Transaction.updates` 로 들어온다. 놓치지 않도록 만들자마자 구독한다.
@MainActor
final class StoreKitPurchaseClient: PurchaseClient {
    /// App Store Connect 의 광고 제거 상품 ID.
    /// `kr.co.carve.leetaek.removeads` 는 한 번 만들었다 지워서 다시 쓸 수 없다(App Store Connect 는 삭제한 상품 ID 를 재사용하지 못한다).
    static let removeAdsProductID = "kr.co.carve.leetaek.adfree"

    @Shared(.isAdFree) private var isAdFree
    private var product: Product?
    private var updates: Task<Void, Never>?
    private var initialCheck: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    /// 실행 뒤 첫 권한 판정이 끝나기를 기다렸다가 광고 제거 여부를 돌려준다.
    /// 판정은 한 번만 하고, 이후의 변화는 `Transaction.updates` 가 반영한다.
    func resolveAdFree() async -> Bool {
        let check = initialCheck ?? Task { await refreshEntitlement() }
        initialCheck = check
        await check.value
        return isAdFree
    }

    func removeAdsProduct() async throws(PurchaseClientError) -> RemoveAdsProduct {
        let product = try await loadProduct()
        return RemoveAdsProduct(displayName: product.displayName, displayPrice: product.displayPrice)
    }

    func purchaseRemoveAds() async throws(PurchaseClientError) -> PurchaseOutcome {
        let product = try await loadProduct()
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw .failed(message: String(describing: error))
        }

        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refreshEntitlement()
            return .purchased
        case .success(.unverified):
            throw .verificationFailed
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws(PurchaseClientError) -> RestoreOutcome {
        do {
            // Apple 계정 확인을 띄울 수 있다. 사용자가 명시적으로 복원을 눌렀을 때만 부른다.
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            throw .failed(message: String(describing: error))
        }
        await refreshEntitlement()
        return isAdFree ? .restored : .nothingToRestore
    }

    private func loadProduct() async throws(PurchaseClientError) -> Product {
        if let product { return product }
        let products: [Product]
        do {
            products = try await Product.products(for: [Self.removeAdsProductID])
        } catch {
            throw .failed(message: String(describing: error))
        }
        guard let product = products.first else { throw .productNotFound }
        self.product = product
        return product
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        // 검증된 거래만 마친다. 검증에 실패한 거래는 권한을 주지 않는다.
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refreshEntitlement()
    }

    /// 현재 권한을 다시 판정해 공유 값에 쓴다. 환불 · 취소된 거래는 권한으로 치지 않는다.
    private func refreshEntitlement() async {
        var hasEntitlement = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.removeAdsProductID,
                  transaction.revocationDate == nil else { continue }
            hasEntitlement = true
        }
        $isAdFree.withLock { $0 = hasEntitlement }
    }
}
