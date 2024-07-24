//
//  AppVersionView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

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
                    Image(asset: ResourcesAsset.xButton)
                        .resizable()
                        .frame(width: 50, height: 50, alignment: .center)
                    
                    
                }
                Button {
                    store.send(.pushToLisence)
                } label: {
                    Text("라이센스")
                        .foregroundStyle(.black)
                }

            }
        } destination: { store in
            switch store.case {
            case .lisence(let store):
                LisenceView(store: store)
            }
        }
    }
}
