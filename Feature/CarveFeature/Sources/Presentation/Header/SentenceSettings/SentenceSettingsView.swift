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
    /// 화면 언어 — 묶음 제목 · 항목 이름 · 글꼴 이름을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<SentenceSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CarvePanelHeader(CarveFeatureCatalog.string("본문 설정", locale: locale)) {
                    Button { dismiss() } label: { Text("완료", bundle: .module) }
                        .buttonStyle(.carve(.primary))
                }

                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    CarveSettingsSection(CarveFeatureCatalog.string("글꼴", locale: locale)) {
                        CarveSegmentedPicker(selection: $store.setting.fontFamily.sending(\.setFontFamily), items: FontCase.allCases) { font in
                            Text(verbatim: Self.fontName(font, locale: locale))
                                .font(CarveTypography.scripture(font.font(size: 14)))
                        }
                    }

                    CarveLabeledSlider(
                        CarveFeatureCatalog.string("글자 크기", locale: locale),
                        value: $store.setting.fontSize.sending(\.setFontSize),
                        in: 15...40,
                        step: 1,
                        valueText: "\(Int(store.setting.fontSize)) pt"
                    )
                    CarveLabeledSlider(
                        CarveFeatureCatalog.string("줄 간격", locale: locale),
                        value: $store.setting.lineSpace.sending(\.setLineSpace),
                        in: 5...70,
                        step: 1,
                        valueText: "\(Int(store.setting.lineSpace))"
                    )
                    CarveLabeledSlider(
                        CarveFeatureCatalog.string("자간", locale: locale),
                        value: $store.setting.traking.sending(\.setTraking),
                        in: 1...10,
                        step: 1,
                        valueText: "\(Int(store.setting.traking))"
                    )
                }
                .padding(CarveSpacing.large)

                CarveDivider()

                CarveSettingsSection(CarveFeatureCatalog.string("화면과 필기", locale: locale)) {
                    CarveSettingsRow(
                        CarveFeatureCatalog.string("왼손 사용자용 화면", locale: locale),
                        description: CarveFeatureCatalog.string("필기 열이 왼쪽으로 가요", locale: locale),
                        isOn: $store.isLeftHanded.sending(\.setLeftHanded)
                    )
                    CarveSettingsRow(
                        CarveFeatureCatalog.string("손가락 필사 허용", locale: locale),
                        description: CarveFeatureCatalog.string("끄면 Apple Pencil로만 필사할 수 있어요", locale: locale),
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
    /// 역할: 글꼴 고르기 칸의 이름(화면 언어). 글꼴 이름은 Domain `FontCase.title(locale:)` 한 곳에서 현지화한다.
    /// 입력 · 출력: 글꼴 · 로케일(뷰는 환경 locale 을 넘긴다) → 이름(ko 「나눔명조」 · en 「Nanum Myeongjo」).
    /// 부작용: 없음.
    static func fontName(_ font: FontCase, locale: Locale) -> String {
        font.title(locale: locale)
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SentenceSettingsFeature()
    }
    SentenceSettingsView(store: store)
}
