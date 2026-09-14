//
//  PurchaseClient.swift
//  ClientInterfaces
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ComposableArchitecture

/// 광고 제거 상품 정보. 가격은 App Store Connect 에서 바뀌므로 앱에 적어 두지 않고 스토어가 준 표시 문자열을 쓴다.
public struct RemoveAdsProduct: Sendable, Equatable, Hashable {
    public let displayName: String
    /// 사용자 지역 통화로 만든 가격 문자열(예: 「₩4,400」)
    public let displayPrice: String

    public init(displayName: String, displayPrice: String) {
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

/// 구매 요청의 결과.
public enum PurchaseOutcome: Sendable, Equatable {
    /// 구매가 끝나 광고 제거 권한이 생겼다.
    case purchased
    /// 보호자 승인(Ask to Buy) 등으로 대기 중. 승인되면 권한은 따로 반영된다.
    case pending
    /// 사용자가 결제 창을 닫았다.
    case cancelled
}

/// 구매 복원의 결과.
public enum RestoreOutcome: Sendable, Equatable {
    case restored
    /// 이 Apple 계정에 광고 제거 구매 내역이 없다.
    case nothingToRestore
    /// 사용자가 Apple 계정 확인을 닫았다.
    case cancelled
}

/// 구매 관련 에러
public enum PurchaseClientError: Error, Sendable, Equatable {
    /// 스토어에서 상품을 찾지 못함(상품 미등록 · 계약 미완료 · 네트워크)
    case productNotFound
    /// 거래 서명을 검증하지 못함 — 권한을 주지 않는다.
    case verificationFailed
    case failed(message: String)
}

/// 광고 제거 일회성 구매(비소모성).
/// - StoreKit 구현과 권한 판정은 App 타겟에서 한다. 판정 결과는 ``SharedReaderKey/isAdFree`` 로 퍼진다.
public protocol PurchaseClient: Sendable {
    @MainActor
    func removeAdsProduct() async throws(PurchaseClientError) -> RemoveAdsProduct

    @MainActor
    func purchaseRemoveAds() async throws(PurchaseClientError) -> PurchaseOutcome

    /// App Store 와 거래 내역을 맞춘 뒤 권한을 다시 판정한다.
    @MainActor
    func restorePurchases() async throws(PurchaseClientError) -> RestoreOutcome
}

private enum PurchaseClientKey: DependencyKey {
    static let liveValue: any PurchaseClient = UnimplementedPurchaseClient()
    static let testValue: any PurchaseClient = UnimplementedPurchaseClient()
}

public extension DependencyValues {
    var purchaseClient: any PurchaseClient {
        get { self[PurchaseClientKey.self] }
        set { self[PurchaseClientKey.self] = newValue }
    }
}

private struct UnimplementedPurchaseClient: PurchaseClient {
    @MainActor
    func removeAdsProduct() async throws(PurchaseClientError) -> RemoveAdsProduct {
        throw .productNotFound
    }

    @MainActor
    func purchaseRemoveAds() async throws(PurchaseClientError) -> PurchaseOutcome {
        throw .productNotFound
    }

    @MainActor
    func restorePurchases() async throws(PurchaseClientError) -> RestoreOutcome {
        .nothingToRestore
    }
}
