//
//  iCloudSettingView.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: CloudSettingsFeature.self)
public struct CloudSettingView: View {
    @Bindable public var store: StoreOf<CloudSettingsFeature>
    
    public init(store: StoreOf<CloudSettingsFeature>) {
        self.store = store
    }
    
    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    Text("iCloud")
                        .font(CarveTypography.sectionTitle)
                        .foregroundStyle(CarveColor.secondary)

                    CarveSettingsRow(
                        "iCloud를 저장공간으로 사용",
                        description: "항상 켜져 있어요. 끄기는 설정 앱에서 할 수 있어요.",
                        isOn: $store.iCloudIsOn.sending(\.setiCloud)
                    )
                    .disabled(true)

                    CarveDivider()

                    VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
                        Text("필사한 내용을 개인 iCloud 계정에 백업해요.")
                            .foregroundStyle(CarveColor.ink)
                        Text("쓰지 않으면 앱을 지울 때 필사도 함께 사라져요.")
                        Text("끄기는 다음 업데이트에서 제공할 예정이에요.")
                    }
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)

                    CarveDivider()

                    VStack(alignment: .leading, spacing: CarveSpacing.small) {
                        Text("위험한 동작")
                            .font(CarveTypography.sectionTitle)
                            .foregroundStyle(CarveColor.secondary)

                        Button {
                            send(.databaseIsEmpty)
                        } label: {
                            Text("모든 필사 데이터 삭제")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.carve(.destructive, fillsWidth: true))
                        .popover(item: $store.scope(state: \.path?.popup, action: \.path.popup)) { store in
                            PopupView(store: store)
                        }

                        Text("모든 장의 필사 기록이 사라져요. 되돌릴 수 없어요.")
                            .font(CarveTypography.caption)
                            .foregroundStyle(CarveColor.secondary)
                    }
                }
                .padding(CarveSpacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CarveColor.surface)
            
            if store.isLoading {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThickMaterial)
                    )
            }
        }
        .disabled(store.isLoading)
    }
    
        
}
