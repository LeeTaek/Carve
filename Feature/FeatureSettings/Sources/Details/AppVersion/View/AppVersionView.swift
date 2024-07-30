//
//  AppVersionView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI
import Resources

import ComposableArchitecture

public struct AppVersionView: View {
    @Bindable private var store: StoreOf<AppVersionReducer>
    
    public init(store: StoreOf<AppVersionReducer>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            List {
                Section("앱 정보") {
                    appVersion
                }
                
//                Button {
//                    store.send(.pushToLisence)
//                } label: {
//                    HStack {
//                        Text("라이센스")
//                            .foregroundStyle(.black)
//                        Spacer()
//                        Image(systemName: "chevron.forward")
//                            .foregroundStyle(.black)
//                    }
//                }
            }
        } destination: { store in
            switch store.case {
            case .lisence(let store):
                LisenceView(store: store)
            }
        }
    }
    
    private var appVersion: some View {
        HStack {
            Image(asset: ResourcesAsset.appIcon)
                .resizable()
                .frame(width: 50, height: 50, alignment: .center)
            Text("새기다")
            Spacer()
            Text(UIDevice.appVersion())
                .padding(.horizontal)
        }
    }
    
    
}
