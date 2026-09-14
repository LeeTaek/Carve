//
//  AdConsentCoordinator.swift
//  CarveApp
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import ClientInterfaces

/// 광고 동의(UMP)를 모으고, 광고를 요청해도 되는 때 광고 SDK 를 시작한다(ADS-1).
///
/// - 앱을 실행할 때마다 동의 정보를 갱신한다. EEA·영국·스위스처럼 동의가 필요한 지역에서만 폼이 뜬다.
/// - 이전 실행에서 이미 광고를 요청할 수 있었다면 갱신을 기다리지 않고 바로 시작해 첫 광고를 늦추지 않는다.
/// - 광고 로드는 ``canRequestAds()`` 로 동의 확인이 끝나기를 기다린다.
@MainActor
final class AdConsentCoordinator: AdConsentClient {
    private var gathering: Task<Void, Never>?
    private var isMobileAdsStarted = false

    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// 동의 정보를 갱신하고 필요하면 폼을 띄운다. 여러 번 불러도 한 번만 수행한다.
    func gatherConsent() async {
        if gathering == nil {
            gathering = Task {
                startMobileAdsIfAllowed()
                do {
                    try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                    try await ConsentForm.loadAndPresentIfRequired(from: RootViewControllerProvider.topMostViewController())
                } catch {
                    // 네트워크 오류 등으로 갱신에 실패해도 이전 실행에서 저장된 동의 상태(canRequestAds)로 진행한다.
                }
                startMobileAdsIfAllowed()
            }
        }
        await gathering?.value
    }

    /// 광고를 요청해도 되는지. 동의 확인이 끝날 때까지 기다린다.
    func canRequestAds() async -> Bool {
        await gatherConsent()
        return ConsentInformation.shared.canRequestAds
    }

    func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: RootViewControllerProvider.topMostViewController())
    }

    private func startMobileAdsIfAllowed() {
        guard !isMobileAdsStarted, ConsentInformation.shared.canRequestAds else { return }
        isMobileAdsStarted = true
        // 성경 앱이라 모든 광고 요청을 전체 이용가(G)로 제한한다. 첫 요청 전에 적용되도록 start 보다 먼저 둔다.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .general
        MobileAds.shared.start()
    }
}
