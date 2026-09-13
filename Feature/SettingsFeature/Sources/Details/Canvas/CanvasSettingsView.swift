//
//  CanvasSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: CanvasSettingsFeature.self)
public struct CanvasSettingsView: View {
    @Bindable public var store: StoreOf<CanvasSettingsFeature>

    public init(store: StoreOf<CanvasSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text("필사 캔버스")
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                CarveSettingsRow(
                    "단일 캔버스 사용",
                    description: "장 전체를 하나의 캔버스에서 필사해요.",
                    isOn: $store.isSingleCanvasEnabled.sending(\.view.setSingleCanvasEnabled)
                )

                CarveDivider()

                Text("켜거나 끄면 현재 장을 다시 불러와요. 두 방식은 같은 필사 데이터를 사용하므로 언제든 되돌릴 수 있어요.")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .onAppear { send(.onAppear) }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        CanvasSettingsFeature()
    }
    CanvasSettingsView(store: store)
}
