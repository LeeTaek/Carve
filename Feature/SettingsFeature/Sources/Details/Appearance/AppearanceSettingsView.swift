//
//  AppearanceSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: AppearanceSettingsFeature.self)
public struct AppearanceSettingsView: View {
    public let store: StoreOf<AppearanceSettingsFeature>
    /// 고른 화면 모드. 세그먼트는 이 값을 보여 주고, 바꾸면 리듀서가 같은 키에 쓴다.
    @SharedReader(.appearanceMode) private var appearanceMode: AppearanceMode

    public init(store: StoreOf<AppearanceSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                CarveSettingsSection("화면 모드") {
                    CarveSegmentedPicker(
                        selection: Binding(
                            get: { appearanceMode },
                            set: { send(.setAppearanceMode($0)) }
                        ),
                        items: AppearanceMode.allCases
                    ) { mode in
                        Text(mode.title)
                    }
                }

                CarveDivider()

                Text("「시스템 설정」을 고르면 iPad의 라이트·다크 설정을 따라가요. 원문과 필기가 있는 종이 영역은 다크 모드에서도 밝게 보여요.")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
    }
}

extension AppearanceMode {
    /// 설정 화면(사이드바 값 · 세그먼트)에 적는 이름.
    var title: String {
        switch self {
        case .system: "시스템 설정"
        case .light: "라이트"
        case .dark: "다크"
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        AppearanceSettingsFeature()
    }
    AppearanceSettingsView(store: store)
}
