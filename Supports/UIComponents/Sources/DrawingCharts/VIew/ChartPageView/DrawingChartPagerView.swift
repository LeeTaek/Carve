//
//  DrawingChartPagerView.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: DrawingChartPagerFeature.self)
public struct DrawingChartPagerView: View {
    @Bindable public var store: StoreOf<DrawingChartPagerFeature>
    
    public init(store: StoreOf<DrawingChartPagerFeature>) {
        self.store = store
    }
    
    
    public var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                ForEach(
                    store.scope(state: \.chartPageState,
                                action: \.chartPageAction),
                    id: \.state.id
                ) { childStore in
                    DrawingChartPageView(store: childStore)
                }
                .frame(width: proxy.size.width)
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .animation(store.animation, value: store.translation)
            .offset(x: -CGFloat(store.index) * proxy.size.width)
            .offset(x: store.translation)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        send(.dragUpdated(traslation: value.translation.width))
                    }
                    .onEnded { value in
                        send(.dragOnEnded(translation: value.translation.width,
                                          width: proxy.size.width))
                    }
            )
        }
    }
}
