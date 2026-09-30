//
//  AdSlotFeature.swift
//  UIComponents
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit
import ClientInterfaces

import ComposableArchitecture

/// 네이티브 광고 한 자리의 로드 상태. 차트 · 탐색 사이드바 · 필사 헤더가 같은 규칙을 쓴다.
///
/// - 실패하거나 광고 제거를 사면 자리를 없앤다(시안 K4). 화면은 ``State/hasAd`` · ``State/occupiesSpace`` 로 표시 여부를 정한다.
/// - 받은 광고는 ``adLifetime`` 뒤 만료된다. 계속 보이는 자리는 바로 새로 받고, 가끔 보이는 자리는 비웠다가 다음에 열 때 받는다.
@Reducer
public struct SponsorAdSlotFeature {
    /// 네이티브 광고를 받은 뒤 보여줄 수 있는 시간. AdMob 은 1시간이 지나면 만료된다고 안내한다.
    public static let adLifetime: Duration = .seconds(60 * 60)

    public init() {}

    @ObservableState
    public struct State {
        /// 광고 슬롯이 어떤 위치에 표시되는지 구분하기 위한 값
        public let placement: NativeAdPlacement
        /// 만료되면 바로 새로 받을지. 계속 보이는 자리(헤더)는 true, 가끔 보이는 자리(사이드바 · 차트)는 false.
        public let refreshesOnExpiry: Bool
        /// 광고 제거를 샀는지. 설정에서 사면 액션 없이도 화면에서 자리가 바로 사라진다.
        @SharedReader(.isAdFree) public var isAdFree: Bool
        /// AdMob 로드 성공시 반환받는 토큰(뷰 캐시 조회용)
        public var token: NativeAdToken?
        /// 로딩 중인지 여부
        public var isLoading = false
        /// 로딩 실패시 진단용 에러메세지
        public var errorMessage: String?
        /// 토큰에 매핑된 광고 UIView
        public var adView: UIView?

        /// 그릴 광고가 있는지.
        public var hasAd: Bool { !isAdFree && adView != nil }

        /// 자리를 차지하는지. 로드 중에는 광고가 도착해도 주변이 밀리지 않게 비워 두고, 실패하거나 광고 제거를 사면 없앤다.
        public var occupiesSpace: Bool { !isAdFree && (isLoading || hasAd) }

        public init(
            placement: NativeAdPlacement,
            refreshesOnExpiry: Bool = false,
            token: NativeAdToken? = nil,
            isLoading: Bool = false,
            errorMessage: String? = nil
        ) {
            self.placement = placement
            self.refreshesOnExpiry = refreshesOnExpiry
            self.token = token
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }

    public enum Action {
        /// 로딩 시작. 이미 광고가 있거나 받는 중이면 무시한다.
        case startLoad
        /// 로딩 성공: token 반환
        case adLoaded(NativeAdToken)
        /// 로딩 실패: 에러 메세지
        case adFailed(String)
        /// 받은 광고가 만료됨
        case adExpired
    }

    private enum CancelID: Hashable {
        case expiry(NativeAdPlacement)
    }

    @Dependency(\.nativeAdClient) var nativeAdClient
    @Dependency(\.continuousClock) var clock

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startLoad:
                // 광고 제거를 샀으면 요청하지 않고, 남아 있는 광고가 있으면 정리한다.
                guard state.isAdFree == false else { return clear(&state) }
                // 이미 있으면 재요청 안 함
                guard state.token == nil, state.isLoading == false else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                return load(placement: state.placement)

            case .adLoaded(let token):
                // 받는 사이에 광고 제거를 샀으면 받은 광고를 버린다.
                guard state.isAdFree == false else {
                    invalidate(token)
                    return clear(&state)
                }
                // 만료로 새로 받은 경우 이전 광고 뷰를 정리한다.
                if let previous = state.token, previous != token {
                    invalidate(previous)
                }
                state.isLoading = false
                let adView = MainActor.assumeIsolated {
                    nativeAdClient.view(for: token)
                }
                // 토큰은 왔는데 그릴 뷰가 없으면 실패와 같다 — 빈 자리를 만료 때까지 잡아 두지 않는다.
                guard let adView else {
                    invalidate(token)
                    state.token = nil
                    state.adView = nil
                    state.errorMessage = "광고 뷰를 찾지 못함"
                    return .none
                }
                state.token = token
                state.adView = adView
                return .run { [clock] send in
                    try await clock.sleep(for: Self.adLifetime)
                    await send(.adExpired)
                }
                .cancellable(id: CancelID.expiry(state.placement), cancelInFlight: true)

            case .adFailed(let message):
                // 실패하면 자리를 없앤다. 만료 뒤 새로 받다가 실패했으면 만료된 광고도 내린다.
                if let previous = state.token {
                    invalidate(previous)
                }
                state.isLoading = false
                state.token = nil
                state.adView = nil
                state.errorMessage = message
                return .none

            case .adExpired:
                guard let expired = state.token, state.isLoading == false else { return .none }
                if state.isAdFree {
                    return clear(&state)
                }
                if state.refreshesOnExpiry {
                    // 새 광고가 올 때까지 이전 광고를 그대로 두어 자리가 깜빡이지 않게 한다.
                    state.isLoading = true
                    return load(placement: state.placement)
                }
                invalidate(expired)
                state.token = nil
                state.adView = nil
                return .none
            }
        }
    }

    private func load(placement: NativeAdPlacement) -> Effect<Action> {
        .run { send in
            do {
                let token = try await nativeAdClient.load(placement: placement)
                await send(.adLoaded(token))
            } catch {
                await send(.adFailed(String(describing: error)))
            }
        }
    }

    /// 광고 제거를 산 뒤 남은 광고 · 로드 상태 · 만료 타이머를 정리한다.
    private func clear(_ state: inout State) -> Effect<Action> {
        if let token = state.token {
            invalidate(token)
        }
        state.token = nil
        state.adView = nil
        state.isLoading = false
        state.errorMessage = nil
        return .cancel(id: CancelID.expiry(state.placement))
    }

    private func invalidate(_ token: NativeAdToken) {
        MainActor.assumeIsolated {
            nativeAdClient.invalidate(token: token)
        }
    }
}

extension SponsorAdSlotFeature.State: Equatable {
    /// 광고 뷰는 같은 인스턴스인지로 비교한다.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.placement == rhs.placement
            && lhs.refreshesOnExpiry == rhs.refreshesOnExpiry
            && lhs.isAdFree == rhs.isAdFree
            && lhs.token == rhs.token
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
            && lhs.adView === rhs.adView
    }
}
