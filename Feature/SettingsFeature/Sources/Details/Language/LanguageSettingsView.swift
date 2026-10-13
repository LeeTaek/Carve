//
//  LanguageSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 10/12/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

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
                    HStack(spacing: CarveSpacing.medium) {
                        // 언어를 바꾸면 iOS 가 앱을 새로 시작하므로 화면이 떠 있는 동안 값이 바뀌지 않는다 — 그릴 때 한 번 읽는다.
                        Text(verbatim: AppLanguage.current().nativeName)
                            .font(CarveTypography.body)
                            .foregroundStyle(CarveColor.ink)
                        Spacer(minLength: 0)
                        Button {
                            send(.openSystemSettingsTapped)
                        } label: {
                            Text("iPad 설정에서 바꾸기", bundle: .module)
                        }
                        .buttonStyle(.carve(.secondary))
                    }
                }

                CarveDivider()

                VStack(alignment: .leading, spacing: CarveSpacing.small) {
                    Text("iPad 설정 앱의 새기다 화면에서 「언어」를 고르면 한국어와 English 중에 바꿀 수 있어요. 언어를 바꾸면 앱이 새로 시작돼요.", bundle: .module)
                    Text("성경 번역본은 앱 언어와 따로 골라요. 필사 화면의 제목을 눌러 바꿔요.", bundle: .module)
                }
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

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        LanguageSettingsFeature()
    }
    LanguageSettingsView(store: store)
}
