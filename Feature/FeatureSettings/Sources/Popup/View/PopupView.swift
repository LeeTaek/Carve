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
        VStack {
            if store.title != nil {
                Text(store.title!)
                    .bold()
            }
            Text(store.body)
            
            HStack {
                Button {
                    store.send(.confirm)
                } label: {
                    Text(store.confirmTitle)
                        .foregroundStyle(store.confirmColor)
                }
                .padding()
                if store.cancelTitle != nil {
                    Spacer()
                    Button {
                        store.send(.cancel)
                    } label: {
                        Text(store.cancelTitle!)
                    }
                    .padding()
                }
            }
        }
        .padding()
    }
    
    
}
