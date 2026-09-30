//
//  RemoveAdsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import Combine
import Foundation

import ComposableArchitecture

/// 광고 제거 일회성 구매(시안 K4 네 번째 프레임). 설정에 조용히 두고 구매를 권하는 팝업은 띄우지 않는다.
///
/// 구매 여부의 기준은 앱의 구매 클라이언트가 쓰는 `@Shared(.isAdFree)` 하나다. 구매 · 복원 결과로 상태를 직접 바꾸지 않고
/// 그 값을 구독해 옮긴다 — 보호자 승인처럼 화면 밖에서 끝나는 구매도 같은 길로 반영된다.
/// 상태에 `@SharedReader` 를 두지 않는 이유는 `SettingsFeature.Path` 가 `Hashable` 상태를 요구하고
/// `SharedReader` 는 `Hashable` 이 아니기 때문이다.
@Reducer
public struct RemoveAdsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        /// 광고 제거를 샀는지
        public var isAdFree = false
        /// 스토어에서 받은 상품. 가격은 앱에 적어 두지 않고 여기서 받은 표시 문자열을 쓴다.
        public var product: RemoveAdsProduct?
        public var isLoadingProduct = false
        /// 진행 중인 요청. 끝날 때까지 구매 · 복원 버튼을 막는다.
        public var inProgress: StoreRequest?
        /// 결과 안내
        public var notice: Notice?

        public init() { }
    }

    public enum StoreRequest: Hashable, Sendable {
        case purchase
        case restore
    }

    public enum Notice: Hashable, Sendable {
        /// 보호자 승인 대기
        case pending
        case nothingToRestore
        /// 스토어에서 상품을 찾지 못함
        case productUnavailable
        case purchaseFailed
        case restoreFailed
    }

    public enum Action: ViewAction {
        case adFreeChanged(Bool)
        case productResponse(Result<RemoveAdsProduct, PurchaseClientError>)
        case purchaseResponse(Result<PurchaseOutcome, PurchaseClientError>)
        case restoreResponse(Result<RestoreOutcome, PurchaseClientError>)
        case view(View)

        public enum View {
            case onAppear
            case purchaseTapped
            case restoreTapped
            /// 화면이 사라짐 — 권한 구독을 끊는다.
            case onDisappear
        }
    }

    private enum CancelID {
        case adFree
    }

    @Dependency(\.purchaseClient) private var purchaseClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onDisappear):
                return .cancel(id: CancelID.adFree)

            case .view(.onAppear):
                let isAdFree = SharedReader<Bool>(.isAdFree)
                let observeAdFree = Effect<Action>.publisher {
                    isAdFree.publisher.map(Action.adFreeChanged)
                }
                .cancellable(id: CancelID.adFree, cancelInFlight: true)

                guard state.product == nil, state.isLoadingProduct == false else { return observeAdFree }
                state.isLoadingProduct = true
                return .merge(observeAdFree, loadProduct())

            case .adFreeChanged(let isAdFree):
                state.isAdFree = isAdFree
                if isAdFree {
                    state.notice = nil
                }

            case .productResponse(.success(let product)):
                state.isLoadingProduct = false
                state.product = product

            case .productResponse(.failure):
                // 가격을 못 받아도 조용히 둔다. 구매를 누르면 상품을 다시 받으며, 그때 실패하면 안내한다.
                state.isLoadingProduct = false

            case .view(.purchaseTapped):
                guard state.isAdFree == false, state.inProgress == nil else { return .none }
                state.inProgress = .purchase
                state.notice = nil
                return purchase()

            case .purchaseResponse(let result):
                state.inProgress = nil
                switch result {
                case .success(.purchased), .success(.cancelled):
                    // 구매 완료는 공유 권한을 통해 반영된다. 결제 창을 닫았으면 아무 안내도 하지 않는다.
                    break
                case .success(.pending):
                    state.notice = .pending
                case .failure(.productNotFound):
                    state.notice = .productUnavailable
                case .failure:
                    state.notice = .purchaseFailed
                }

            case .view(.restoreTapped):
                guard state.inProgress == nil else { return .none }
                state.inProgress = .restore
                state.notice = nil
                return restore()

            case .restoreResponse(let result):
                state.inProgress = nil
                switch result {
                case .success(.restored), .success(.cancelled):
                    break
                case .success(.nothingToRestore):
                    state.notice = .nothingToRestore
                case .failure:
                    state.notice = .restoreFailed
                }
            }
            return .none
        }
    }

    private func loadProduct() -> Effect<Action> {
        .run { [purchaseClient] send in
            let result: Result<RemoveAdsProduct, PurchaseClientError>
            do throws(PurchaseClientError) {
                result = .success(try await purchaseClient.removeAdsProduct())
            } catch {
                result = .failure(error)
            }
            await send(.productResponse(result))
        }
    }

    private func purchase() -> Effect<Action> {
        .run { [purchaseClient] send in
            let result: Result<PurchaseOutcome, PurchaseClientError>
            do throws(PurchaseClientError) {
                result = .success(try await purchaseClient.purchaseRemoveAds())
            } catch {
                result = .failure(error)
            }
            await send(.purchaseResponse(result))
        }
    }

    private func restore() -> Effect<Action> {
        .run { [purchaseClient] send in
            let result: Result<RestoreOutcome, PurchaseClientError>
            do throws(PurchaseClientError) {
                result = .success(try await purchaseClient.restorePurchases())
            } catch {
                result = .failure(error)
            }
            await send(.restoreResponse(result))
        }
    }
}
