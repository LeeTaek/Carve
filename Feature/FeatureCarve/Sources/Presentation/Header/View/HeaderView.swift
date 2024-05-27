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
        return HStack {
            Button(action: { store.send(.titleDidTapped) }) {
                Text("\(titleName) \(store.state.currentTitle.chapter)장")
                    .font(.system(size: 30))
                    .padding()
            }
            Spacer()
            
        }
        .background {
            Color.white
                .ignoresSafeArea()
        }
        .padding(.top, safeArea().top)
        .padding(.bottom, 20)
        .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(HeaderBoundsKey.self) { value in
            GeometryReader { proxy in
                if let anchor = value {
                    Color.clear
                        .onAppear {
                            store.send(.setHeaderHeight(proxy[anchor].height))
                        }
                }
            }
        }
        .offset(y: -store.headerOffset < store.headerOffset
                ? store.headerOffset
                : (store.headerOffset < 0 ? store.headerOffset : 0))
        .ignoresSafeArea(.all, edges: .top)
    }
}
