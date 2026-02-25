//
//  AdSlotFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit
import ClientInterfaces

import ComposableArchitecture

@Reducer
public struct SponsorAdSlotFeature {
    @ObservableState
    public struct State {
        /// 광고 슬롯이 어떤 위치에 표시되는지 구분하기 위한 값 (Chart에선 card)
        let placement: NativeAdPlacement
        /// AdMob 로드 성공시 반환받는 토큰(뷰 캐시 조회용)
        var token: NativeAdToken?
        /// 로딩 중인지 여부
        var isLoading = false
        /// 로딩 실패시 사용자용 에러메세지
        var errorMessage: String?
        /// 토큰에 매핑된 광고 UIView
        var adView: UIView?

        init(
            placement: NativeAdPlacement,
            token: NativeAdToken? = nil,
            isLoading: Bool = false,
            errorMessage: String? = nil
        ) {
            self.placement = placement
            self.token = token
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }
    @Dependency(\.nativeAdClient) var nativeAdClient

    public enum Action {
        /// 로딩 시작
        case startLoad
        /// 로딩 성공: token 반환
        case adLoaded(NativeAdToken)
        /// 로딩 성공: 에러 메세지
        case adFailed(String)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startLoad:
                // 이미 있으면 재요청 안 함
                guard state.token == nil, state.isLoading == false else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                
                let placement = state.placement

                return .run { send in
                    do {
                        let token = try await nativeAdClient.load(placement: placement)
                        await send(.adLoaded(token))
                    } catch {
                        await send(.adFailed(String(describing: error)))
                    }
                }
                
            case .adLoaded(let token):
                state.isLoading = false
                state.token = token

                state.adView = MainActor.assumeIsolated {
                    nativeAdClient.view(for: token)
                }
                return .none
                
            case .adFailed(let message):
                state.isLoading = false
                state.errorMessage = message
                return .none
            }
        }
    }
}
