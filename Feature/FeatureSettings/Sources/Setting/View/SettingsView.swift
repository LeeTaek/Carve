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
        NavigationSplitView {
            sideBar()
        } detail: {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        store.send(.backToCarve)
                    } label: {
                        Image(asset: ResourcesAsset.xButton)
                            .resizable()
                            .frame(width: 35, height: 35)
                            .padding()

                    }
                }
                .padding()
                detailView()
                Spacer()
            }
            .toolbar(.hidden)
        }

    }
    
    @ViewBuilder
    private func sideBar() -> some View {
        VStack {
            Text("설정")
                .font(.system(.title3))
                .fontWeight(.semibold)
            List(selection: $store.path.sending(\.push)) {
                Section("환경 설정") {
                    NavigationLink("iCloud 설정", value: SettingsReducer.Path.State.iCloud(.initialState))
                }
                Section("앱 설정") {
                    NavigationLink("앱 버전", value: SettingsReducer.Path.State.appVersion(.initialState))
                    NavigationLink("라이센스", value: SettingsReducer.Path.State.lisence(.initialState))
                }
            }
        }
        .toolbar(.hidden)
    }
    
    
    @ViewBuilder
    private func detailView() -> some View {
        switch store.path {
        case .iCloud:
            if let store = store.scope(state: \.path?.iCloud, action: \.path.iCloud) {
                CloudSettingView(store: store)
            }
        case .appVersion:
            if let store = store.scope(state: \.path?.appVersion, action: \.path.appVersion) {
                AppVersionView(store: store)
            }
        case .lisence:
            if let store = store.scope(state: \.path?.lisence, action: \.path.lisence) {
                LisenceView(store: store)
            }
        default:
            fatalError("Not Defined Settings View")
        }
    }
}
