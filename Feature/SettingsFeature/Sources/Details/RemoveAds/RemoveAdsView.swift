//
//  RemoveAdsView.swift
//  SettingsFeature
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 광고 제거 구매 화면(시안 K4 네 번째 프레임) — 한 줄 설명 · 구매 · 구매 복원만 둔다.
@ViewAction(for: RemoveAdsFeature.self)
public struct RemoveAdsView: View {
    @Bindable public var store: StoreOf<RemoveAdsFeature>

    public init(store: StoreOf<RemoveAdsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text("광고 제거")
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                if store.isAdFree {
                    CarveSettingsRow("광고 없이 쓰는 중", description: "광고 제거를 구매했어요.", value: "구매함")
                } else {
                    CarveSettingsRow("광고 없이 쓰기", description: priceDescription, value: "")
                    actions
                }

                CarveDivider()

                Text("사이드바 · 필사 화면 · 차트의 광고가 모두 사라져요.")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notice = store.notice {
                    Text(notice.message)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .onAppear { send(.onAppear) }
        .onDisappear { send(.onDisappear) }
    }

    private var actions: some View {
        HStack(spacing: CarveSpacing.small) {
            Button("구매") {
                send(.purchaseTapped)
            }
            .buttonStyle(.carve(.primary))

            Button("구매 복원") {
                send(.restoreTapped)
            }
            .buttonStyle(.carve(.secondary))

            if store.inProgress != nil {
                ProgressView()
                    .accessibilityLabel(store.inProgress == .restore ? "구매 내역 확인 중" : "구매 진행 중")
            }
        }
        .disabled(store.inProgress != nil)
    }

    private var priceDescription: String {
        if let product = store.product {
            return "한 번 구매 · \(product.displayPrice)"
        }
        return store.isLoadingProduct ? "가격을 불러오는 중" : "한 번 구매"
    }
}

private extension RemoveAdsFeature.Notice {
    var message: String {
        switch self {
        case .pending:
            "구매 승인을 기다리고 있어요. 승인되면 광고가 사라져요."
        case .nothingToRestore:
            "이 Apple 계정에서 복원할 구매 내역이 없어요."
        case .productUnavailable:
            "지금은 구매할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .purchaseFailed:
            "구매를 마치지 못했어요. 다시 시도해 주세요."
        case .restoreFailed:
            "구매 내역을 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        RemoveAdsFeature()
    }
    RemoveAdsView(store: store)
}
