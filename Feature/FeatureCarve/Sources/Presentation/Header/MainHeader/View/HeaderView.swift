//
//  HeaderView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct HeaderView: View {
    private var store: StoreOf<HeaderReducer>
    public  init(store: StoreOf<HeaderReducer>) {
        self.store = store
    }
    
    public var body: some View {
        let titleName = store.currentTitle.title.koreanTitle()
        return VStack {
            HStack {
                Button(action: { store.send(.titleDidTapped) }) {
                    Text("\(titleName) \(store.state.currentTitle.chapter)장")
                        .font(.system(size: 30))
                        .padding()
                }
                Spacer()
                pencilConfigButton
                sentenceSettingsButton
            }
            
            if store.showPalatte {
                PencilPalatteView(store: store.scope(state: \.palatteSetting,
                                                     action: \.palatteAction))
            }
        }
        .background {
            Color.white
                .ignoresSafeArea()
        }
        .padding(.top, safeArea().top)
        .padding(.bottom, 20)
        .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(HeaderBoundsKey.self) { value in
            if value != nil {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { proxySize in
                        store.send(.setHeaderHeight(proxySize))
                    }
            }
        }
        .offset(y: -store.headerOffset < store.headerOffset
                ? store.headerOffset
                : (store.headerOffset < 0 ? store.headerOffset : 0))
        .ignoresSafeArea(.all, edges: .top)
    }
    
    private var pencilConfigButton: some View {
        Button {
            store.send(.pencilConfigDidTapped)
        } label: {
            Image(asset: FeatureCarveAsset.pencilConfig)
                .resizable()
                .frame(width: 30, height: 30)
                .padding(10)
        }
    }
    
    private var sentenceSettingsButton: some View {
        Button {
            store.send(.sentenceSettingsDidTapped)
        } label: {
            Image(asset: FeatureCarveAsset.sentenceConfig)
                .resizable()
                .frame(width: 30, height: 30)
                .padding([.trailing], 20)
        }
        
    }
}
