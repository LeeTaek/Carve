//
//  ColorPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents

import ComposableArchitecture

@ViewAction(for: ColorPalatteFeature.self)
public struct ColorPalatteView: View {
    @Bindable public var store: StoreOf<ColorPalatteFeature>
    public init(store: StoreOf<ColorPalatteFeature>) {
        self.store = store
    }
    
    public var body: some View {
        Form {
            Section(
                header: Text("펜 색상").font(.headline)
            ) {
                LazyHGrid(rows: Array(repeating: GridItem(), count: 2)) {
                    ForEach(store.colors) { color in
                        Circle()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(Color.init(uiColor: color))
                            .opacity(store.alpha)
                            .scaleEffect(store.selectedColor.color == color ? 0.7 : 1)
                            .overlay {
                                Circle()
                                    .stroke(lineWidth: 3)
                                    .foregroundColor(store.selectedColor.color == color ? .white : .clear)
                            }
                            .onTapGesture {
                                send(.setColor(color))
                            }
                            .padding()
                    }
                }
                .padding()
                .frame(width: 400, height: 180)
            }
            
            Section(
                header: Text("투명도: \(String(format: "%.2f", store.alpha))").font(.headline)
            ) {
                CustomSlider(
                    value: $store.alpha.sending(\.setAlpha),
                    minValue: 0,
                    maxValue: 1,
                    isFloat: true
                )
                .padding()
            }
            
        }
        .scrollDisabled(true)
        .frame(width: 400, height: 400)
    }
}
