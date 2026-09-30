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
                CarvePanelHeader("본문 설정") {
                    Button("완료") { dismiss() }
                        .buttonStyle(.carve(.primary))
                }

                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    CarveSettingsSection("글꼴") {
                        CarveSegmentedPicker(selection: $store.setting.fontFamily.sending(\.setFontFamily), items: FontCase.allCases) { font in
                            Text(font.title)
                                .font(CarveTypography.scripture(font.font(size: 14)))
                        }
                    }

                    CarveLabeledSlider("글자 크기", value: $store.setting.fontSize.sending(\.setFontSize), in: 15...40, step: 1, valueText: "\(Int(store.setting.fontSize)) pt")
                    CarveLabeledSlider("줄 간격", value: $store.setting.lineSpace.sending(\.setLineSpace), in: 5...70, step: 1, valueText: "\(Int(store.setting.lineSpace))")
                    CarveLabeledSlider("자간", value: $store.setting.traking.sending(\.setTraking), in: 1...10, step: 1, valueText: "\(Int(store.setting.traking))")
                }
                .padding(CarveSpacing.large)

                CarveDivider()

                CarveSettingsSection("화면과 필기") {
                    CarveSettingsRow("왼손 사용자용 화면", description: "필기 열이 왼쪽으로 가요", isOn: $store.isLeftHanded.sending(\.setLeftHanded))
                    CarveSettingsRow("손가락 필사 허용", description: "끄면 Apple Pencil로만 필사할 수 있어요", isOn: $store.allowFingerDrawing.sending(\.setAllowFingerDrawing))
                }
                .padding(.horizontal, CarveSpacing.large)
                .padding(.vertical, CarveSpacing.medium)

                CarveDivider()

                Button("본문 모양 초기화") {
                    store.send(.resetSetting)
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

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SentenceSettingsFeature()
    }
    SentenceSettingsView(store: store)
}
