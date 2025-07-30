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

public struct SentenceSettingsView: View {
    @Bindable private var store: StoreOf<SentenceSettingsFeature>
    public init(store: StoreOf<SentenceSettingsFeature>) {
        self.store = store
    }
    
    public var body: some View {
        Form {
            Section(
                header: Text("예시 문구").font(.headline).bold()
            ) {
                SentenceView(store: self.store.scope(state: \.sampleSentence,
                                                     action: \.sampleSentence)
                )
                .frame(height: 300, alignment: .center)
            }
            
            Section(
                header: Text("폰트").font(.headline).bold()
            ) {
                SegmentedPicker(
                    selection: $store.setting.fontFamily,
                    items: Domain.FontCase.allCases) { font in
                        Text(font.title)
                            .font(Font(font.font(size: 20)))
                    }
            }
            
            Section(
                header: Text("폰트 크기: \(Int(store.setting.fontSize))").font(.headline).bold()
            ) {
                CustomSlider(
                    value: $store.setting.fontSize,
                    minValue: 15,
                    maxValue: 40
                )
                .padding(.vertical)
            }
            Section(
                header: Text("줄 간격: \(Int(store.setting.lineSpace))").font(.headline).bold()
            ) {
                CustomSlider(
                    value: $store.setting.lineSpace,
                    minValue: 5,
                    maxValue: 70
                )
                .padding(.vertical)
            }
            Section(
                header: Text("글자 간격: \(Int(store.setting.traking))").font(.headline).bold()
            ) {
                CustomSlider(
                    value: $store.setting.traking,
                    minValue: 1,
                    maxValue: 10
                )
                .padding(.vertical)
            }
        }
    }
}
