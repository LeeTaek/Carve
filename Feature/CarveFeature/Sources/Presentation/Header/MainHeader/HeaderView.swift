//
//  HeaderView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import Resources

import ComposableArchitecture

@ViewAction(for: HeaderFeature.self)
public struct HeaderView: View {
    public var store: StoreOf<HeaderFeature>
    private let iconSize: CGFloat = 30
    public  init(store: StoreOf<HeaderFeature>) {
        self.store = store
    }
    
    public var body: some View {
        let titleName = store.currentTitle.title.koreanTitle()
        return VStack {
            HStack {
                Button(action: { send(.titleDidTapped) }) {
                    Text("\(titleName) \(store.currentTitle.chapter)장")
                        .font(Font(ResourcesFontFamily.NanumGothic.bold.font(size: 30)))
                        .foregroundStyle(.black.opacity(0.7))
                        .padding()
                }
                Spacer()
                if !store.showOnlyTitle {
                    beforeButton
                    nextButton
                    divider
                    pencilConfigButton
                    sentenceSettingsButton
                }
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
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { proxySize in
                                    send(.setHeaderHeight(proxySize))
                                }
                        }
                    )
            }
        }
        .offset(y: -store.headerOffset < store.headerOffset
                ? store.headerOffset
                : (store.headerOffset < 0 ? store.headerOffset : 0))
        .ignoresSafeArea(.all, edges: .top)
    }
    
    private var pencilConfigButton: some View {
        Button {
            send(.pencilConfigDidTapped)
        } label: {
            Image(asset: CarveFeatureAsset.pencilConfig)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var sentenceSettingsButton: some View {
        Button {
            send(.sentenceSettingsDidTapped)
        } label: {
            Image(asset: CarveFeatureAsset.sentenceConfig)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var nextButton: some View {
        Button {
            send(.moveToNext)
        } label: {
            Image(asset: CarveFeatureAsset.next)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(15)
        }
    }
    
    private var beforeButton: some View {
        Button {
            send(.moveToBefore)
        } label: {
            Image(asset: CarveFeatureAsset.before)
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
