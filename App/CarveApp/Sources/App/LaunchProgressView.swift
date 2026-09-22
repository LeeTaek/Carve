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
import UIComponents

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
                    if store.offersStartFirst {
                        // 초기 복원에서는 **처음부터** 둔다 — 20초를 기다리게 하지 않는다(정책 §3-1, 사용자 결정 2026-09-21).
                        // 「계속 기다리기」 는 따로 버튼 없이 이 화면에 머무는 것이다.
                        Button(startFirstTitle) {
                            send(.startFirstTapped)
                        }
                        .buttonStyle(.carve(.primary))
                    }
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
    
    /// 「먼저 시작하기」 의 제목. 확인된 오류로 기다릴 것이 없으면 「시작하기」 다.
    private var startFirstTitle: String {
        if case .failed = store.syncState { return "시작하기" }
        return "먼저 시작하기"
    }

    /// CloudKit 동기화 상태에 따라 적절한 안내 문구(에러/진행/완료).
    @ViewBuilder
    func cloudkitSyncStateMessage(state: PersistentCloudKitContainer.CloudSyncState) -> some View {
        switch state {
        case .idle, .syncing, .stillWaiting:
            waitingText
        case .migration:
            statusText("데이터 마이그레이션 중...\n조금만 기다려주세요.")
        case .failed(let reason):
            failureText(reason)
        case .storeUnavailable(let failure):
            storeUnavailableText(failure)
        case .syncCompleted:
            statusText("데이터 동기화 완료")
        case .connectionHeld:
            // C14 연결 보류 — 들어가되 이 실행은 이 기기에만 저장한다. 까닭과 다시 시도는 필사 화면의 띠 · 설정이 말한다(정책 §12-6 C14 ③).
            statusText("지금은 이 기기에만 저장하는 상태로 시작해요")
        default: EmptyView()
        }
    }

    /// 결론이 나기 전의 안내 — 대기 방식에 따라 다르다.
    ///
    /// 초기 복원은 20초 · 60초에 **안내만** 바꾼다(들어가지 않는다). 먼저 시작해도 늦게 도착한 필사는 열린 장에 반영하거나 알린다 —
    /// 그 약속은 `ChapterCanvasArrivalFeature` 가 지킨다(2026-09-21 후속 리뷰 P0-3). 예전 문구 "먼저 시작해도 나중에 나타날 수 있어요" 는
    /// 지켜지지 않던 약속이었다.
    @ViewBuilder
    private var waitingText: some View {
        switch store.mode {
        case .initialRestore?:
            switch store.stage {
            case .checking:
                statusText("iCloud에 저장된 필사를 확인하고 있어요.\n\(Self.arrivalPromise)")
            case .slow:
                statusText("기존 필사를 불러오는 데 시간이 걸리고 있어요.\n계속 기다리거나 먼저 시작할 수 있어요.\n\(Self.arrivalPromise)")
            case .verySlow:
                statusText("아직 기존 필사를 받고 있어요.\n필사가 많거나 네트워크가 느리면 오래 걸릴 수 있어요.\n\(Self.arrivalPromise)")
            }
        case .normal?:
            // 이 기기에 필사가 있다 — 기다리지 않고 들어간다. 동기화는 앱 안에서 계속 본다.
            statusText("필사를 여는 중이에요")
        case nil:
            statusText("초기화 중...")
        }
    }

    /// 먼저 시작했을 때 늦게 도착한 필사가 어떻게 되는지 — 편집하지 않은 장은 반영하고, 편집한 장은 알린다.
    private static let arrivalPromise = "먼저 시작해도 기존 필사는 도착하는 대로 화면에 반영하거나 알려 드려요."

    /// 로컬 저장소를 쓸 수 없을 때의 안내. **iCloud · 네트워크 안내와 섞지 않는다** — 들어가지 않는 이유와 할 수 있는 일을 말한다
    /// (정책 §3 표 4행).
    ///
    /// - Important: **보장할 수 있는 것만 말한다.** 앱이 저장소를 지우거나 V1 폴백을 하지 않은 것은 확실하지만,
    ///              앱 스키마로 여는 첫 시도가 파일을 전혀 바꾸지 않았다는 보장은 없다(2026-09-17 리뷰). 그래서
    ///              "지우거나 바꾸지 않았어요" 대신 "시작을 멈췄어요" 로 말한다. 업데이트만 제시하면 막다른 안내가 되므로
    ///              **앱을 지우지 말라는 당부와 문의 경로**를 함께 둔다 — 지우면 이 기기의 필사가 사라진다.
    @ViewBuilder
    private func storeUnavailableText(_ failure: LocalStoreFailure) -> some View {
        let reason = switch failure {
        case .unknownVersion:
            // 더 새 버전일 수도, 버전을 올리지 않고 고친 스키마일 수도 있다 — 업데이트가 늘 해결책은 아니다.
            "이 버전의 앱이 알아보지 못하는 필사 저장소예요.\n앱을 최신 버전으로 업데이트하면 열릴 수 있어요."
        case .openFailed:
            // 마이그레이션 실패 등. 원인을 특정하지 못하므로 원인을 말하지 않는다.
            "필사 저장소를 준비하지 못했어요.\n앱을 완전히 종료한 뒤 다시 열어 주세요."
        case .unreadable:
            "필사 저장소를 읽지 못했어요.\n앱을 완전히 종료한 뒤 다시 열어 주세요."
        case .preservationFailed:
            // 원시 사본(정책 §12-6 C3 ①)을 만들지 못했다. 공간이 모자란 경우가 가장 흔하다.
            "새 형식으로 옮기기 전에 기존 필사를 따로 보관하지 못했어요.\n기기 저장 공간을 확보한 뒤 앱을 다시 열어 주세요."
        }
        Text("필사를 지키려고 시작을 멈췄어요.\n\(reason)\n\(Self.keepAppAdvice)")
            .font(.subheadline)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    /// 막힌 경우에 공통으로 붙이는 당부. **앱을 지우면 이 기기의 필사가 사라진다.**
    private static var keepAppAdvice: String {
        let address = UserFeedback.initialState.feedbackAddress
        return address.isEmpty
            ? "앱을 지우지 마세요. 같은 안내가 계속되면 알려 주세요."
            : "앱을 지우지 마세요. 같은 안내가 계속되면 \(address) 로 알려 주세요."
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
