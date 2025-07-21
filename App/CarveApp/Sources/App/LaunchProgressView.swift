//
//  LaunchProgressView.swift
//  Carve
//
//  Created by 이택성 on 1/31/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit
import Domain

import ComposableArchitecture

@ViewAction(for: LaunchProgressFeature.self)
struct LaunchProgressView: View {
    @Bindable public var store: StoreOf<LaunchProgressFeature>
    
    public init(store: StoreOf<LaunchProgressFeature>) {
        self.store = store
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image("LaunchScreen")
                        .resizable()
                        .frame(width: 150, height: 150)
                        .position(
                            x: geometry.size.width / 2,
                            y: (geometry.size.height) / 2 * 0.8
                        )
                    ProgressView(value: store.syncProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.gray)
                        .frame(width: 150)
                    cloudkitSyncStateMessage(state: store.syncState)
                    Spacer()
                }
            }
        }
        .onAppear {
            send(.onAppear)
        }
        .alert("데이터 마이그레이션이 완료", isPresented: $store.shouldShowMigrationAlert.sending(\.view.setMigratioinAlert)) {
            Button("확인", role: .cancel) {
                exit(0)
            }
        } message: {
            Text("앱을 재실행해주세요.")
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    func cloudkitSyncStateMessage(state: PersistentCloudKitContainer.CloudSyncState) -> some View {
        switch state {
        case .idle:
            Text("초기화 중...")
                .font(.subheadline)
                .foregroundColor(.gray)
        case .syncing:
            Text("데이터 동기화 중... \(Int(store.syncProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.gray)
        case .migration:
            Text("데이터 마이그레이션 중...\n조금만 기다려주세요. \(Int(store.syncProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.gray)
        case .success:
            Text("데이터 동기화 완료")
                .font(.subheadline)
                .foregroundColor(.gray)
        case .failed:
            Text("❗️iCloud에서 데이터를 가져오는데 실패했습니다.\n네트워크를 확인해주세요.")
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        case .nextScene:
            EmptyView()
        }
    }
}
