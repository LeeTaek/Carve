//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import Resources

import ComposableArchitecture

@ViewAction(for: SettingsFeature.self)
public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsFeature>
    
    public init(store: StoreOf<SettingsFeature>) {
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
        .toolbar(.hidden)
    }
    
    private var sideBar: some View {
        List(selection: $store.path.sending(\.push)) {
            Section("앱 설정") {
                NavigationLink("iCloud 설정", value: SettingsFeature.Path.State.iCloud(.initialState))
            }
            Section("지원") {
                NavigationLink("의견 보내기", value: SettingsFeature.Path.State.sendFeedback(.initialState))
                NavigationLink("앱 버전", value: SettingsFeature.Path.State.appVersion(.initialState))
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
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SettingsFeature()
    }
    SettingsView(store: store)
}
