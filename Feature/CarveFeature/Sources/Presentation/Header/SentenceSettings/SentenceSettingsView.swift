//
//  SentenceSettingsView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

public struct SentenceSettingsView: View {
    @Bindable private var store: StoreOf<SentenceSettingsFeature>
    @Environment(\.dismiss) private var dismiss

    public init(store: StoreOf<SentenceSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CarvePanelHeader(String(localized: "본문 설정", bundle: .module)) {
                    Button { dismiss() } label: { Text("완료", bundle: .module) }
                        .buttonStyle(.carve(.primary))
                }

                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    CarveSettingsSection(String(localized: "글꼴", bundle: .module)) {
                        CarveSegmentedPicker(selection: $store.setting.fontFamily.sending(\.setFontFamily), items: FontCase.allCases) { font in
                            Text(verbatim: Self.fontName(font))
                                .font(CarveTypography.scripture(font.font(size: 14)))
                        }
                    }

                    CarveLabeledSlider(
                        String(localized: "글자 크기", bundle: .module),
                        value: $store.setting.fontSize.sending(\.setFontSize),
                        in: 15...40,
                        step: 1,
                        valueText: "\(Int(store.setting.fontSize)) pt"
                    )
                    CarveLabeledSlider(
                        String(localized: "줄 간격", bundle: .module),
                        value: $store.setting.lineSpace.sending(\.setLineSpace),
                        in: 5...70,
                        step: 1,
                        valueText: "\(Int(store.setting.lineSpace))"
                    )
                    CarveLabeledSlider(
                        String(localized: "자간", bundle: .module),
                        value: $store.setting.traking.sending(\.setTraking),
                        in: 1...10,
                        step: 1,
                        valueText: "\(Int(store.setting.traking))"
                    )
                }
                .padding(CarveSpacing.large)

                CarveDivider()

                CarveSettingsSection(String(localized: "화면과 필기", bundle: .module)) {
                    CarveSettingsRow(
                        String(localized: "왼손 사용자용 화면", bundle: .module),
                        description: String(localized: "필기 열이 왼쪽으로 가요", bundle: .module),
                        isOn: $store.isLeftHanded.sending(\.setLeftHanded)
                    )
                    CarveSettingsRow(
                        String(localized: "손가락 필사 허용", bundle: .module),
                        description: String(localized: "끄면 Apple Pencil로만 필사할 수 있어요", bundle: .module),
                        isOn: $store.allowFingerDrawing.sending(\.setAllowFingerDrawing)
                    )
                }
                .padding(.horizontal, CarveSpacing.large)
                .padding(.vertical, CarveSpacing.medium)

                CarveDivider()

                Button {
                    store.send(.resetSetting)
                } label: {
                    Text("본문 모양 초기화", bundle: .module)
                }
                .buttonStyle(.carve(.primary, fillsWidth: true))
                .disabled(store.setting == .initialState)
                .padding(CarveSpacing.large)
            }
        }
        .frame(idealWidth: 350)
        .carvePresentationSurface()
    }
}

extension SentenceSettingsView {
    /// 역할: 글꼴 고르기 칸의 이름(앱 언어). 글꼴 이름(`FontCase.title`)은 Domain 의 한국어 고정 문구라 화면에서 카탈로그로 바꾼다.
    /// 입력 · 출력: 글꼴 · 로케일(nil 이면 앱 언어) → 이름(ko 「나눔명조」 · en 「Myeongjo」).
    /// 부작용: 없음.
    static func fontName(_ font: FontCase, locale: Locale? = nil) -> String {
        switch font {
        case .myeongjo: CarveFeatureCatalog.string("나눔명조", locale: locale)
        case .gothic: CarveFeatureCatalog.string("나눔바른고딕", locale: locale)
        case .flower: CarveFeatureCatalog.string("나눔꽃향기", locale: locale)
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SentenceSettingsFeature()
    }
    SentenceSettingsView(store: store)
}
