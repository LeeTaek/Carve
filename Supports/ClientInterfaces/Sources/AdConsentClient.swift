//
//  AdConsentClient.swift
//  ClientInterfaces
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ComposableArchitecture

/// 광고 동의(UMP) 상태와 개인정보 옵션 폼.
/// - 동의 수집과 광고 SDK 시작은 App 타겟에서 구현한다. Feature 는 설정 항목 노출 여부와 폼 열기만 쓴다.
public protocol AdConsentClient: Sendable {
    /// 설정에 개인정보 옵션 진입점을 둬야 하는지(EEA·영국·스위스 등). 동의 정보를 갱신하기 전에는 false.
    @MainActor
    var isPrivacyOptionsRequired: Bool { get }

    /// 광고 개인정보 옵션 폼을 띄운다.
    @MainActor
    func presentPrivacyOptions() async throws
}

private enum AdConsentClientKey: DependencyKey {
    static let liveValue: any AdConsentClient = UnimplementedAdConsentClient()
    static let testValue: any AdConsentClient = UnimplementedAdConsentClient()
}

public extension DependencyValues {
    var adConsentClient: any AdConsentClient {
        get { self[AdConsentClientKey.self] }
        set { self[AdConsentClientKey.self] = newValue }
    }
}

private struct UnimplementedAdConsentClient: AdConsentClient {
    @MainActor
    var isPrivacyOptionsRequired: Bool { false }

    @MainActor
    func presentPrivacyOptions() async throws {}
}
