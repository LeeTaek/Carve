//
//  GoogleAdClient.swift
//  CarveApp
//
//  Created by 이택성 on 1/8/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit
import GoogleMobileAds
import ClientInterfaces
import UIComponents

enum AdMobConfig {
    /// 위치별 네이티브 광고 단위. Debug 는 Google 테스트 단위, Release 는 실제 단위를 빌드 설정에서 넣는다.
    static func nativeAdUnitId(for placement: NativeAdPlacement) -> String {
        let key = switch placement {
        case .chartCard: "ADMOB_NATIVE_CHART_AD_UNIT_ID"
        case .sidebarCard: "ADMOB_NATIVE_SIDEBAR_AD_UNIT_ID"
        case .headerStrip: "ADMOB_NATIVE_HEADER_AD_UNIT_ID"
        }
        return Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

private extension NativeAdPlacement {
    /// 위치별 광고 레이아웃
    var contentStyle: NativeAdContentView.Style {
        switch self {
        case .chartCard: .card
        case .sidebarCard: .sidebar
        case .headerStrip: .headerStrip
        }
    }

    /// 위치별 로더 옵션. 미디어(이미지 · 동영상)는 차트 카드만 16:9 로 그리므로 가로형 소재를 선호한다고 알린다(보장은 아님).
    /// 사이드바 · 헤더는 미디어를 그리지 않는다. 동영상만 골라 빼는 요청 옵션은 SDK 에 없어,
    /// 미디어 유형은 AdMob 콘솔의 광고 단위 설정으로 정한다(헤더 · 사이드바 이미지만, 차트 이미지 · 동영상).
    var loaderOptions: [GADAdLoaderOptions]? {
        switch self {
        case .chartCard:
            let mediaOptions = NativeAdMediaAdLoaderOptions()
            mediaOptions.mediaAspectRatio = .landscape
            return [mediaOptions]
        case .sidebarCard, .headerStrip:
            return nil
        }
    }
}

/// GoogleMobileAds 기반 Native 광고 로더.
/// - `load`는 AdMob의 delegate 콜백을 async/await 형태로 바꿔 사용.
/// - 광고 제거를 사지 않았고, 광고 동의(UMP) 확인이 끝나 요청이 허용된 뒤에만 로드한다.
final class GoogleNativeAdClient: NSObject, NativeAdClient, @unchecked Sendable {
    /// 광고 동의 수집과 광고 SDK 시작
    private let consent: AdConsentCoordinator
    /// 광고 제거 권한
    private let purchases: StoreKitPurchaseClient
    /// tokenId -> 실제로 화면에 embed할 광고 UIView 캐시
    private var viewCache: [String: UIView] = [:]

    /// delegate 콜백으로 완료됐을 때 Continuation으로 async/await로 연결
    private struct InFlightRequest {
        let tokenId: String
        let placement: NativeAdPlacement
        let adLoader: AdLoader
        let continuation: CheckedContinuation<Result<NativeAdToken, NativeAdClientError>, Never>
    }

    /// 진행 중인 로드 요청. 차트·사이드바·헤더가 동시에 요청하므로 로더별로 따로 든다.
    /// 같은 위치의 요청만 한 번에 하나로 막는다.
    private var inFlightRequests: [ObjectIdentifier: InFlightRequest] = [:]

    init(consent: AdConsentCoordinator, purchases: StoreKitPurchaseClient) {
        self.consent = consent
        self.purchases = purchases
        super.init()
    }

    /// placement별 adUnitId를 App 타겟에서 해석.
    /// - Feature에서 adUnitId를 모르도록 하고 싶으면 빈 문자열로 호출.
    private func resolvedAdUnitId(
        for placement: NativeAdPlacement,
        provided adUnitId: String
    ) -> String {
        if adUnitId.isEmpty == false { return adUnitId }
        return AdMobConfig.nativeAdUnitId(for: placement)
    }

    /// Native 광고를 로드하고, 성공 시 토큰을 반환.
    @MainActor
    func load(
        placement: NativeAdPlacement,
        adUnitId: String
    ) async throws(NativeAdClientError) -> NativeAdToken {
        let resolvedAdUnitId = resolvedAdUnitId(for: placement, provided: adUnitId)
        guard resolvedAdUnitId.isEmpty == false else {
            throw .emptyAdUnitId
        }

        // 광고 제거를 샀으면 요청하지 않는다. 실행 직후에는 첫 권한 판정을 기다린다.
        guard await purchases.resolveAdFree() == false else {
            throw .adFree
        }

        // 동의 확인이 끝날 때까지 기다린다. 동의가 필요한 지역에서 동의를 받지 못했으면 요청하지 않는다.
        guard await consent.canRequestAds() else {
            throw .consentNotObtained
        }

        guard let rootViewController = RootViewControllerProvider.topMostViewController() else {
            throw .rootViewControllerNotFound
        }

        if inFlightRequests.values.contains(where: { $0.placement == placement }) {
            throw .requestAlreadyInFlight
        }

        let tokenId = UUID().uuidString

        let loader = AdLoader(
            adUnitID: resolvedAdUnitId,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: placement.loaderOptions
        )

        let result = await withCheckedContinuation { continuation in
            loader.delegate = self
            inFlightRequests[ObjectIdentifier(loader)] = InFlightRequest(
                tokenId: tokenId,
                placement: placement,
                adLoader: loader,
                continuation: continuation
            )
            loader.load(Request())
        }

        switch result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        }
    }

    /// 토큰으로 광고 UIView를 조회.
    @MainActor
    func view(for token: NativeAdToken) -> UIView? {
        // load 성공 후에만 캐시에 저장.
        viewCache[token.tokenId]
    }

    /// 토큰에 해당하는 캐시를 정리.
    @MainActor
    func invalidate(token: NativeAdToken) {
        // 메모리 정리(만료로 교체하거나 화면에서 내릴 때 호출)
        viewCache[token.tokenId] = nil
    }
}

extension GoogleNativeAdClient: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let request = inFlightRequests.removeValue(forKey: ObjectIdentifier(adLoader)) else {
            return
        }

        let nativeAdView = NativeAdContainerView(style: request.placement.contentStyle)
        nativeAdView.populate(with: nativeAd)
        viewCache[request.tokenId] = nativeAdView

        request.continuation.resume(returning: .success(NativeAdToken(tokenId: request.tokenId)))
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let request = inFlightRequests.removeValue(forKey: ObjectIdentifier(adLoader)) else {
            return
        }

        let nsError = error as NSError
        request.continuation.resume(
            returning: .failure(.adLoaderFailed(code: nsError.code, message: nsError.localizedDescription))
        )
    }
}
