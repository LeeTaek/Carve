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
    /// 화면 언어 — 앱 안에서 언어를 고르면 행 · 가격 설명 · 안내 문구도 바로 따라온다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<RemoveAdsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text("광고 제거", bundle: .module)
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                if store.isAdFree {
                    CarveSettingsRow(
                        SettingsCatalog.string("광고 없이 쓰는 중", locale: locale),
                        description: SettingsCatalog.string("광고 제거를 구매했어요.", locale: locale),
                        value: SettingsCatalog.string("구매함", locale: locale)
                    )
                } else {
                    CarveSettingsRow(SettingsCatalog.string("광고 없이 쓰기", locale: locale), description: priceDescription, value: "")
                    actions
                }

                CarveDivider()

                Text("사이드바 · 필사 화면 · 차트의 광고가 모두 사라져요.", bundle: .module)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notice = store.notice {
                    Text(notice.message(locale: locale))
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
        // 사라질 때는 보내지 않는다 — 설정이 경로를 바꾸거나 닫으면서 구독을 끝내고, 그 뒤에 온 액션은 받을 상태가 없다(룰북 navigation.md).
        .onAppear { send(.onAppear) }
    }

    private var actions: some View {
        HStack(spacing: CarveSpacing.small) {
            Button {
                send(.purchaseTapped)
            } label: {
                Text("구매", bundle: .module)
            }
            .buttonStyle(.carve(.primary))

            Button {
                send(.restoreTapped)
            } label: {
                Text("구매 복원", bundle: .module)
            }
            .buttonStyle(.carve(.secondary))

            if store.inProgress != nil {
                ProgressView()
                    .accessibilityLabel(store.inProgress == .restore ? Text("구매 내역 확인 중", bundle: .module) : Text("구매 진행 중", bundle: .module))
            }
        }
        .disabled(store.inProgress != nil)
    }

    private var priceDescription: String {
        if let product = store.product {
            return SettingsCatalog.string("한 번 구매 · \(product.displayPrice)", locale: locale)
        }
        return store.isLoadingProduct
            ? SettingsCatalog.string("가격을 불러오는 중", locale: locale)
            : SettingsCatalog.string("한 번 구매", locale: locale)
    }
}

private extension RemoveAdsFeature.Notice {
    /// 안내 한 줄 — 뷰는 환경 `locale` 을 넘긴다. 상태에는 안내의 종류만 두고 문구는 그릴 때 만든다.
    func message(locale: Locale) -> String {
        switch self {
        case .pending:
            SettingsCatalog.string("구매 승인을 기다리고 있어요. 승인되면 광고가 사라져요.", locale: locale)
        case .nothingToRestore:
            SettingsCatalog.string("이 Apple 계정에서 복원할 구매 내역이 없어요.", locale: locale)
        case .productUnavailable:
            SettingsCatalog.string("지금은 구매할 수 없어요. 잠시 뒤 다시 시도해 주세요.", locale: locale)
        case .purchaseFailed:
            SettingsCatalog.string("구매를 마치지 못했어요. 다시 시도해 주세요.", locale: locale)
        case .restoreFailed:
            SettingsCatalog.string("구매 내역을 확인하지 못했어요. 다시 시도해 주세요.", locale: locale)
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        RemoveAdsFeature()
    }
    RemoveAdsView(store: store)
}
