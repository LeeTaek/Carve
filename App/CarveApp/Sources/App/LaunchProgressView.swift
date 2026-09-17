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

/// 앱 최초 실행 시 CloudKit 동기화/마이그레이션 진행 상태를 보여주는 Launch 화면.
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
                    if store.syncState.isInProgress {
                        ProgressView()
                            .tint(.gray)
                            .frame(width: 150)
                    }
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
    
    /// CloudKit 동기화 상태에 따라 적절한 안내 문구(에러/진행/완료).
    @ViewBuilder
    func cloudkitSyncStateMessage(state: PersistentCloudKitContainer.CloudSyncState) -> some View {
        switch state {
        case .idle:
            statusText("초기화 중...")
        case .syncing:
            statusText("데이터 동기화 중...")
        case .migration:
            statusText("데이터 마이그레이션 중...\n조금만 기다려주세요.")
        case .stillWaiting:
            // 실패가 아니다. 관찰은 계속되고 원격 필사가 나중에 도착할 수 있다 (정책 §3-2).
            statusText("기존 필사를 확인하는 데 시간이 걸리고 있어요.\n먼저 시작해도 나중에 나타날 수 있어요.")
        case .failed(let reason):
            failureText(reason)
        case .syncCompleted:
            statusText("데이터 동기화 완료")
        default: EmptyView()
        }
    }
    
    /// 확인된 오류의 안내. **원인과 무관한 문구를 쓰지 않는다** — 계정 문제에 "네트워크를 확인" 이라고
    /// 말하면 사용자가 고칠 수 없는 곳을 보게 된다.
    @ViewBuilder
    private func failureText(_ reason: CloudSyncFailure) -> some View {
        let message = switch reason {
        case .accountUnavailable:
            "iCloud 계정을 확인해 주세요.\n지금은 이 기기에만 저장돼요."
        case .accountCheckFailed:
            // 계정이 없다고 단정하지 않는다. 동기화가 되는지도 모르므로 "이 기기에만" 이라고 하지 않는다.
            "iCloud 계정 상태를 확인하지 못했어요.\n필사는 이 기기에 저장돼요."
        case .importFailed:
            "iCloud에서 필사를 가져오다 문제가 생겼어요.\n지금은 이 기기에만 저장돼요."
        case .exportFailed:
            // 받지 못한 것과 올리지 못한 것은 다르다. 후자는 기기에는 남아 있다.
            "필사를 iCloud에 올리지 못했어요.\n이 기기에는 저장돼 있어요."
        case .setupFailed:
            // 시작 화면은 setup 이벤트로 결론을 내지 않는다. 종류가 늘어 문구만 둔다.
            "iCloud 동기화를 준비하지 못했어요.\n필사는 이 기기에 저장돼요."
        case .unknown:
            "iCloud 연결을 확인하지 못했어요.\n지금은 이 기기에만 저장돼요."
        }
        Text(message)
            .font(.subheadline)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
    }

    /// 공통 상태 메시지 스타일(폰트/색상/정렬)을 적용하는 헬퍼 뷰.
    @ViewBuilder
    private func statusText(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
    }
}
