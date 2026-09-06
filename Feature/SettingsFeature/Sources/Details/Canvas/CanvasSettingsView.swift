//
//  CanvasSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: CanvasSettingsFeature.self)
public struct CanvasSettingsView: View {
    @Bindable public var store: StoreOf<CanvasSettingsFeature>

    public init(store: StoreOf<CanvasSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section(
                header: Text("단일 캔버스"),
                footer: Text("장 전체를 캔버스 하나로 필사합니다 (실험 기능). 켜거나 끄면 현재 장을 다시 불러옵니다.\n두 방식은 같은 필사 데이터를 쓰므로 언제든 되돌릴 수 있습니다.")
            ) {
                Toggle(isOn: $store.isSingleCanvasEnabled.sending(\.view.setSingleCanvasEnabled)) {
                    Text("단일 캔버스 사용")
                }
            }
        }
        .navigationTitle("필사 캔버스")
        .onAppear { send(.onAppear) }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        CanvasSettingsFeature()
    }
    CanvasSettingsView(store: store)
}
