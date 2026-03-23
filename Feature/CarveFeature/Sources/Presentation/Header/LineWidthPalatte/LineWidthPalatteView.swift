//
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents

import ComposableArchitecture

public struct LineWidthPalatteView: View {
    @Bindable private var store: StoreOf<LineWidthPalatteFeature>
    public init(store: StoreOf<LineWidthPalatteFeature>) {
        self.store = store
    }
    
    public var body: some View {
        Form {
            Section(
                header: Text("펜 두께: \(String(format: "%.2f", store.lineWidth))").font(.headline)
            ) {
                CustomSlider(
                    value: $store.lineWidth.sending(\.setWidth),
                    minValue: 1,
                    maxValue: 15,
                    isFloat: true
                )
                
            }
        }
        .scrollDisabled(true)
        .frame(width: 300, height: 100)
    }
}
