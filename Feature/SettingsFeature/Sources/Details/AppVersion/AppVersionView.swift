//
//  AppVersionView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI
import Resources

import ComposableArchitecture
import UIComponents

/// 설정 → 앱 버전. 다른 설정 화면과 같은 틀(제목 한 줄 · 설정 묶음 · 값을 오른쪽에 적는 행)로 둔다(시안 F 「앱 버전 · 값」).
public struct AppVersionView: View {
    @Bindable private var store: StoreOf<AppVersionFeature>

    public init(store: StoreOf<AppVersionFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            content
                .toolbar(.hidden, for: .navigationBar)
        } destination: { store in
            switch store.case {
            case .lisence(let store):
                LisenceView(store: store)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text("앱 버전")
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                appIdentity

                CarveDivider()

                CarveSettingsSection("앱 정보") {
                    CarveSettingsRow("버전", value: UIDevice.appVersion())
                    #if DEBUG
                    // 개발 빌드에서만 — 어느 빌드를 시험하는지 가린다. 출시 빌드에는 보이지 않는다.
                    if let build = Self.buildNumber {
                        CarveSettingsRow("빌드", value: build)
                    }
                    #endif
                }
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
    }

    /// 앱 아이콘과 이름 · 버전.
    private var appIdentity: some View {
        HStack(spacing: CarveSpacing.medium) {
            Image(asset: ResourcesAsset.appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CarveColor.divider, lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                Text("새기다")
                    .font(CarveTypography.title)
                    .foregroundStyle(CarveColor.ink)
                Text("버전 \(UIDevice.appVersion())")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    /// 빌드 번호(`CFBundleVersion`) — 개발 빌드에서만 보인다.
    private static var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
    #endif
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        AppVersionFeature()
    }
    AppVersionView(store: store)
}
