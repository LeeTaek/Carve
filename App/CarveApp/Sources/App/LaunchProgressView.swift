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
        .alert(restartAlertTitle, isPresented: $store.shouldShowMigrationAlert.sending(\.view.setMigratioinAlert)) {
            Button("확인", role: .cancel) {
                exit(0)
            }
        } message: {
            Text(restartAlertMessage)
        }
        .ignoresSafeArea()
    }

    /// 재실행 안내 제목. import 가 **성공으로** 끝났을 때만 "완료" 라고 말한다.
    private var restartAlertTitle: String {
        store.syncState == .migrationCompleted ? "데이터 마이그레이션이 완료" : "앱을 다시 실행해 주세요"
    }

    /// 재실행 안내 본문. 마이그레이션 모드는 결론이 무엇이든 들어가지 않는다 — 이번 실행의 저장소로는 필사를 저장할 수 없다.
    private var restartAlertMessage: String {
        switch store.syncState {
        case .migrationEndedWithoutImport(.accountUnavailable?):
            // iCloud 를 쓰지 않는 기기다. 받을 필사가 없으므로 iCloud 를 말하지 않는다.
            "이 기기의 필사를 새 형식으로 옮기려면 앱을 다시 실행해야 해요."
        case .migrationEndedWithoutImport:
            "이 기기의 필사를 새 형식으로 옮기려면 앱을 다시 실행해야 해요.\niCloud에서 필사를 받았는지는 확인하지 못했어요."
        default:
            "앱을 재실행해주세요."
        }
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
        case .storeUnavailable(let failure):
            storeUnavailableText(failure)
        case .syncCompleted:
            statusText("데이터 동기화 완료")
        default: EmptyView()
        }
    }

    /// 로컬 저장소를 쓸 수 없을 때의 안내. **iCloud · 네트워크 안내와 섞지 않는다** — 들어가지 않는 이유와 할 수 있는 일을 말한다
    /// (정책 §3 표 4행).
    @ViewBuilder
    private func storeUnavailableText(_ failure: LocalStoreFailure) -> some View {
        let message = switch failure {
        case .unknownVersion:
            // 저장소를 열지 않고 가렸고 파일을 바꾸지 않았다(`LocalStoreLoadFailureTesting` 이 바이트로 확인한다).
            "필사 저장소를 열 수 없어 시작하지 않았어요.\n더 새 버전의 앱에서 쓰던 저장소로 보여요. 앱을 최신 버전으로 업데이트해 주세요.\n"
                + "저장된 필사는 지우거나 바꾸지 않았어요."
        case .openFailed:
            // 마이그레이션 실패 등. 원인을 특정하지 못하므로 원인을 말하지 않는다.
            "필사 저장소를 준비하지 못해 시작하지 않았어요.\n앱을 완전히 종료한 뒤 다시 열어 주세요.\n앱은 저장된 필사를 지우지 않았어요."
        case .unreadable:
            "필사 저장소를 읽지 못해 시작하지 않았어요.\n앱을 완전히 종료한 뒤 다시 열어 주세요.\n앱은 저장된 필사를 지우지 않았어요."
        }
        Text(message)
            .font(.subheadline)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
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
