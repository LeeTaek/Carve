//
//  LanguageSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: LanguageSettingsFeature.self)
public struct LanguageSettingsView: View {
    public let store: StoreOf<LanguageSettingsFeature>

    public init(store: StoreOf<LanguageSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                CarveSettingsSection(SettingsCatalog.string("앱 언어")) {
                    CarveSegmentedPicker(
                        selection: Binding(
                            get: { store.selection },
                            set: { send(.selectionChanged($0)) }
                        ),
                        items: AppLanguageSelection.allCases
                    ) { selection in
                        Text(selection.title)
                    }
                }

                CarveDivider()

                VStack(alignment: .leading, spacing: CarveSpacing.small) {
                    Text("고른 언어는 바로 적용돼요. 일부 화면은 앱을 다시 열면 바뀌어요.", bundle: .module)
                    Text("성경 번역본은 앱 언어와 따로 골라요. 필사 화면의 제목을 눌러 바꿔요.", bundle: .module)
                }
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

                // 보조 경로 — 설정 앱에서 바꾸면 iOS 가 앱을 종료하고 새 언어로 다시 연다. 저장값은 위 고르기와 같다.
                Button {
                    send(.openSystemSettingsTapped)
                } label: {
                    Text("iPad 설정에서 바꾸기", bundle: .module)
                        .underline()
                }
                .buttonStyle(.plain)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.secondary)
                .frame(minHeight: CarveSize.minimumHitTarget)
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .onAppear {
            send(.onAppear)
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        LanguageSettingsFeature()
    }
    LanguageSettingsView(store: store)
}
