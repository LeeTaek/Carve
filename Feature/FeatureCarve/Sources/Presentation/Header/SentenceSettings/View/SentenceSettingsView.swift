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
    @Bindable private var store: StoreOf<SentenceSettingsReducer>
    public init(store: StoreOf<SentenceSettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Form {
            Section("예시 문구") {
                SentenceView(store: self.store.scope(state: \.sampleSentence,
                                                     action: \.sampleSentence)
                )
                .frame(height: 300, alignment: .center)
                
                VStack(alignment: .leading) {
                    HStack {
                 
                        Text("폰트 크기: \(Int(store.setting.fontSize))")
                            .fontWeight(.bold)
                            .padding()
                        Spacer()
                        Text("줄 간격: \(Int(store.setting.lineSpace))")
                            .fontWeight(.bold)
                            .padding()
                        Spacer()
                        Text("글자 간격: \(Int(store.setting.traking))")
                            .fontWeight(.bold)
                            .padding()
                    }
                }
            }
            
            Section("폰트") {
                SegmentedPicker(
                    selection: $store.setting.fontFamily.sending(\.setFontFamily),
                    items: Domain.FontCase.allCases) { font in
                        Text(font.title)
                            .font(Font(font.font(size: 20)))
                    }
            }
            
            Section("폰트 크기") {
                CustomSlider(
                    value: $store.setting.fontSize.sending(\.setFontSize),
                    minValue: 15,
                    maxValue: 40
                )
                .frame(height: 80, alignment: .center)
            }
            Section("줄 간격") {
                CustomSlider(
                    value: $store.setting.lineSpace.sending(\.setLineSpace),
                    minValue: 5,
                    maxValue: 70
                )
                .frame(height: 80, alignment: .center)
            }
            Section("글자 간격") {
                CustomSlider(
                    value: $store.setting.traking.sending(\.setTraking),
                    minValue: 1,
                    maxValue: 10
                )
                .frame(height: 80, alignment: .center)
            }
        }
    }
}
