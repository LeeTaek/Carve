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
    private let iconSize: CGFloat = 30
    public  init(store: StoreOf<HeaderReducer>) {
        self.store = store
    }
    
    public var body: some View {
        let titleName = store.currentTitle.title.koreanTitle()
        return VStack {
            HStack {
                Button(action: { store.send(.titleDidTapped) }) {
                    Text("\(titleName) \(store.currentTitle.chapter)장")
                        .font(.system(size: 30))
                        .padding()
                }
                Spacer()
                beforeButton
                nextButton
                divider
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
        .padding(.bottom, 10)
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
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var sentenceSettingsButton: some View {
        Button {
            store.send(.sentenceSettingsDidTapped)
        } label: {
            Image(asset: FeatureCarveAsset.sentenceConfig)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var nextButton: some View {
        Button {
            store.send(.moveToNext)
        } label: {
            Image(asset: FeatureCarveAsset.next)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var beforeButton: some View {
        Button {
            store.send(.moveToBefore)
        } label: {
            Image(asset: FeatureCarveAsset.before)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    
    private var divider: some View {
        Rectangle()
            .frame(width: 1, height: iconSize)
            .foregroundStyle(.gray)
            .padding(.horizontal)
    }
}
