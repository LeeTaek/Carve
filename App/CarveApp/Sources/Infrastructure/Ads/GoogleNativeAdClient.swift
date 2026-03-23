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

enum AdMobConfig {
    static var nativeChartAdUnitId: String {
        Bundle.main.object(forInfoDictionaryKey: "ADMOB_NATIVE_CHART_AD_UNIT_ID") as? String ?? ""
    }
}

/// GoogleMobileAds 기반 Native 광고 로더.
/// - `load`는 AdMob의 delegate 콜백을 async/await 형태로 바꿔 사용.
final class GoogleNativeAdClient: NSObject, NativeAdClient, @unchecked Sendable {
    /// tokenId -> 실제로 화면에 embed할 광고 UIView 캐시
    private var viewCache: [String: UIView] = [:]

    /// delegate 콜백으로 완료됐을 때 Continuation으로 async/await로 연결
    private struct InFlightRequest {
        let tokenId: String
        let adLoader: AdLoader
        let continuation: CheckedContinuation<Result<NativeAdToken, NativeAdClientError>, Never>
    }

    /// 현재 진행 중인 단일 로드 요청(동시 요청은 막는 단순 정책)
    private var inFlightRequest: InFlightRequest?

    /// placement별 adUnitId를 App 타겟에서 해석.
    /// - Feature에서 adUnitId를 모르도록 하고 싶으면 빈 문자열로 호출.
    private func resolvedAdUnitId(
        for placement: NativeAdPlacement,
        provided adUnitId: String
    ) -> String {
        if adUnitId.isEmpty == false { return adUnitId }

        switch placement {
        case .chartCard:
            return AdMobConfig.nativeChartAdUnitId
        default:
            return AdMobConfig.nativeChartAdUnitId
        }
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

        guard let rootViewController = RootViewControllerProvider.topMostViewController() else {
            throw .rootViewControllerNotFound
        }

        if inFlightRequest != nil {
            throw .requestAlreadyInFlight
        }

        let tokenId = UUID().uuidString

        let loader = AdLoader(
            adUnitID: resolvedAdUnitId,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: nil
        )

        let result = await withCheckedContinuation { continuation in
            loader.delegate = self
            inFlightRequest = InFlightRequest(
                tokenId: tokenId,
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
        // 메모리 정리(화면에서 사라질 때 호출)
        viewCache[token.tokenId] = nil
    }
}

extension GoogleNativeAdClient: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let request = inFlightRequest else {
            return
        }

        let nativeAdView = NativeAdContainerView()
        nativeAdView.populate(with: nativeAd)
        viewCache[request.tokenId] = nativeAdView

        request.continuation.resume(returning: .success(NativeAdToken(tokenId: request.tokenId)))
        inFlightRequest = nil
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let request = inFlightRequest else {
            return
        }

        let nsError = error as NSError
        request.continuation.resume(
            returning: .failure(.adLoaderFailed(code: nsError.code, message: nsError.localizedDescription))
        )
        inFlightRequest = nil
    }
}
