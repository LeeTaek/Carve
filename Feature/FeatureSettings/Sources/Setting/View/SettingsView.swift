//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import Resources

import ComposableArchitecture

public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsReducer>

    public init(store: StoreOf<SettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {

            
            Form {
                Section("앱 설정") {
                    Button {
                        store.send(.pushToiCloudSettings)
                    } label: {
                        Text("iCloud 설정")
                            .foregroundStyle(.black)
                            .font(.system(size: 16, weight: .semibold))
                            
                    }
                }
                
                Section("앱 정보") {
                    Button {
                        store.send(.pushToAppVersion)
                    } label: {
                        Text("앱 버전")
                            .foregroundStyle(.black)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Button {
                        store.send(.pushToLisence)
                    } label: {
                        Text("라이센스")
                            .foregroundStyle(.black)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                Button {
                    store.send(.backToCarve)
                } label: {
                    Image(asset: ResourcesAsset.xButton)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .padding()
                }
            }
            .toolbarTitleDisplayMode(.large)
        } destination: { store in
            switch store.case {
            case .iCloud(let store):
                CloudSettingView(store: store)
            case .appVersion(let store):
                AppVersionView(store: store)
            case .lisence(let store):
                LisenceView(store: store)
            }
        }
    }
}
