//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI

import ComposableArchitecture

public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsReducer>

    public init(store: StoreOf<SettingsReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Button(action: { store.send(.backToCarve) }, label: {
                Text("back to carve")
            })
            
            List(selection: $store.selected) {
                ForEach(DetailSettings.allCases) { setting in
                    Button {
                        store.send(.presentDetail(setting))
                    } label: {
                        Text("\(setting.id)")
                    }
                }
            }
        }
    }
}
