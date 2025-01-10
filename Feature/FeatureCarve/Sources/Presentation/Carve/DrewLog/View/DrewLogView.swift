//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import Resources

import ComposableArchitecture

public struct DrewLogView: View {
    @Bindable private var store: StoreOf<DrewLogReducer>
    
    public init(store: StoreOf<DrewLogReducer>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }

    
    public var content: some View {
        VStack {
            Button(action: { store.send(.dismiss) }) {
                Text("DrewLogView")
                    .font(Font(ResourcesFontFamily.NanumGothic.bold
                        .font(size: 30)))
                    .foregroundStyle(.black.opacity(0.7))
                    .padding()
            }
        }
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { DrewLogReducer() },
        withDependencies: {
            $0.drawingData = .previewValue
        }
    )
    DrewLogView(store: store)
}
