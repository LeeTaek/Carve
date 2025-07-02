//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import Resources

import ComposableArchitecture

@ViewAction(for: SettingsReducer.self)
public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsReducer>
    
    public init(store: StoreOf<SettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationSplitView {
            sideBar
        } detail: {
            detailView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            send(.backToCarve)
                        } label: {
                            Image(asset: ResourcesAsset.xButton)
                                .resizable()
                                .frame(width: 35, height: 35)
                                .padding()
                        }
                    }
                }
        }
    }
    
    private var sideBar: some View {
        List(selection: $store.path.sending(\.push)) {
            Section("앱 설정") {
                NavigationLink("iCloud 설정", value: SettingsReducer.Path.State.iCloud(.initialState))
            }
            Section("지원") {
                NavigationLink("의견 보내기", value: SettingsReducer.Path.State.sendFeedback(.initialState))
                NavigationLink("앱 버전", value: SettingsReducer.Path.State.appVersion(.initialState))
            }
        }
        .navigationTitle("설정")
        .toolbar(removing: .sidebarToggle)
    }
    
    
    @ViewBuilder
    private func detailView() -> some View {
        switch store.path {
        case .iCloud:
            if let store = store.scope(state: \.path?.iCloud, action: \.path.iCloud) {
                CloudSettingView(store: store)
            }
        case .sendFeedback:
            if let store = store.scope(state: \.path?.sendFeedback, action: \.path.sendFeedback) {
                SendFeedbackView(store: store)
            }
        case .appVersion:
            if let store = store.scope(state: \.path?.appVersion, action: \.path.appVersion) {
                AppVersionView(store: store)
            }
        default:
            fatalError("Not Defined Settings View")
        }
    }
}
