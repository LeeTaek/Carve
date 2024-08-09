//
//  iCloudSettingView.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct CloudSettingView: View {
    @Bindable private var store: StoreOf<CloudSettingsReducer>
    
    public init(store: StoreOf<CloudSettingsReducer>) {
        self.store = store
    }
    
    public var body: some View {
        List {
            Section(
                header: Text("iCloud"),
                footer: Text("필사한 정보를 개인 계정 iCloud를 통해 백업할지 결정합니다. 사용하지 않는 경우 앱 삭제와 함께 필사 내용이 삭제됩니다.\n끄기 옵션은 추후에 업데이트를 통해 제공되며, 설정앱의 iCloud 항목에서 제거할 수 있습니다.")
            ) {
                Toggle(isOn: $store.iCloudIsOn.sending(\.setiCloud)) {
                    Text("iCloud를 저장공간으로 사용")
                }
                .disabled(true)
            }
            
            Button {
                store.send(.databaseIsEmpty)
            }label: {
                Text("모든 필사 데이터 삭제")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .popover(item: $store.scope(state: \.path?.popup, action: \.path.popup)) { store in
                PopupView(store: store)
            }
        }
        .navigationTitle("iCloud 설정")
    }
    
        
}
