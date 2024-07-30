//
//  PopupView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct PopupView: View {
    @Bindable private var store: StoreOf<PopupReducer>
    
    public init(store: StoreOf<PopupReducer>) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if store.title != nil {
                Text(store.title!)
                    .bold()
            }
            Text(store.body)
                .font(.system(size: 18, weight: .medium))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                .background(.white)

            HStack(spacing: 15) {
                Button {
                    store.send(.confirm)
                } label: {
                    Text(store.confirmTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(store.confirmColor)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .border(Color(uiColor: .systemGroupedBackground), width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if store.cancelTitle != nil {
                    Button {
                        store.send(.cancel)
                    } label: {
                        Text(store.cancelTitle!)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .border(Color(uiColor: .systemGroupedBackground), width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    
                }
            }
            .padding()
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .border(Color(uiColor: .systemGroupedBackground), width: 15)
        .frame(minWidth: 100, minHeight: 100)
        .presentationDetents([.medium, .large])
    }
}
