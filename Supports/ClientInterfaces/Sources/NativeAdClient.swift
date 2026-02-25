//
//  NativeAdClient.swift
//  ClientInterfaces
//
//  Created by 이택성 on 1/8/26.
//

import UIKit

import ComposableArchitecture

/// 네이티브 광고 표시 위치(화면/영역 단위로 분리)
public enum NativeAdPlacement: String, Sendable, Equatable {
    case chartCard
}

/// Feature가 들고 있을 핸들 key
/// - UIView를 State에 넣지 않기 위해 token으로 참조.
public struct NativeAdToken: Sendable, Equatable {
    public let tokenId: String
    
    public init(tokenId: String) {
        self.tokenId = tokenId
    }
}

/// Feature에서 사용될 Interface
/// - 광고 서비스 등록은 App 타겟에서
public protocol NativeAdClient: Sendable {
    @MainActor
    func load(
        placement: NativeAdPlacement,
        adUnitId: String
    ) async throws(NativeAdClientError) -> NativeAdToken
    
    @MainActor
    func view(for token: NativeAdToken) -> UIView?
    
    @MainActor
    func invalidate(token: NativeAdToken)
}


public extension NativeAdClient {
    @MainActor
    func load(
        placement: NativeAdPlacement
    ) async throws(NativeAdClientError) -> NativeAdToken {
        try await load(placement: placement, adUnitId: "")
    }
}

/// 광고 설정 관련 에러
public enum NativeAdClientError: Error, Sendable, Equatable {
    case emptyAdUnitId
    case rootViewControllerNotFound
    case requestAlreadyInFlight
    case adLoaderFailed(code: Int, message: String)
}

private enum NativeAdClientKey: DependencyKey {
    static let liveValue: any NativeAdClient = UnimplementedNativeAdClient()
    static let testValue: any NativeAdClient = UnimplementedNativeAdClient()
}

public extension DependencyValues {
    var nativeAdClient: any NativeAdClient {
        get { self[NativeAdClientKey.self] }
        set { self[NativeAdClientKey.self] = newValue }
    }
}

private struct UnimplementedNativeAdClient: NativeAdClient {
    @MainActor
    func load(placement: NativeAdPlacement, adUnitId: String) async throws(NativeAdClientError) -> NativeAdToken {
        
        return NativeAdToken(tokenId: "unimplemented")
    }
    
    @MainActor
    func view(for token: NativeAdToken) -> UIView? {
        return nil
    }
    
    @MainActor
    func invalidate(token: NativeAdToken) {}
}
