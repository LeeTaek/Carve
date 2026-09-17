//
//  iCloudSettingView.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: CloudSettingsFeature.self)
public struct CloudSettingView: View {
    @Bindable public var store: StoreOf<CloudSettingsFeature>
    
    public init(store: StoreOf<CloudSettingsFeature>) {
        self.store = store
    }
    
    /// 계정 상태 한 줄에 쓸 문구. 아직 확인 중이면 본문이 없다.
    private struct AccountStatusCopy {
        let title: String
        let detail: String
        /// 확인 중에는 흐리게 — 아직 결론이 아니라는 뜻이다.
        var isPending: Bool { detail.isEmpty }
    }

    private var accountStatusCopy: AccountStatusCopy {
        switch store.availability {
        case .checking:
            AccountStatusCopy(title: "iCloud 상태를 확인하는 중이에요", detail: "")
        case .available:
            AccountStatusCopy(title: "iCloud 계정에 연결돼 있어요", detail: "필사가 같은 계정의 다른 기기로 전해져요.")
        case .noAccount:
            AccountStatusCopy(title: "iCloud에 로그인돼 있지 않아요", detail: "지금은 이 기기에만 저장돼요.")
        case .restricted:
            AccountStatusCopy(title: "iCloud 사용이 제한돼 있어요", detail: "기기 설정에서 허용해야 동기화할 수 있어요.")
        case .unknown:
            // 확인 실패와 "계정 없음" 을 같은 문구로 쓰지 않는다.
            AccountStatusCopy(title: "iCloud 상태를 확인하지 못했어요", detail: "계정이 없다는 뜻은 아니에요. 잠시 뒤 다시 열어 보세요.")
        }
    }

    /// 지금 확인된 계정 상태 한 줄. **확인 전에는 연결됐다고 쓰지 않는다.**
    @ViewBuilder
    private var accountStatusRow: some View {
        let copy = accountStatusCopy
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text(copy.title)
                .font(CarveTypography.body)
                .foregroundStyle(copy.isPending ? CarveColor.secondary : CarveColor.ink)
            if !copy.detail.isEmpty {
                Text(copy.detail)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 이번 실행의 동기화 활동 한 줄. **이번 실행**에 한정된 기록임을 문구에 드러낸다.
    @ViewBuilder
    private var syncActivityRow: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            switch store.activity.summary {
            case .noRecord:
                activityLine("이번 실행에서는 아직 주고받은 기록이 없어요", emphasized: false)
            case .running:
                activityLine("동기화하는 중이에요", emphasized: false)
            case .failed(let failure):
                activityLine(failureText(failure), emphasized: true)
            case .succeeded(let lastImport, let lastExport):
                if let lastImport {
                    activityLine("마지막으로 받음 · \(lastImport.formatted(.relative(presentation: .named)))", emphasized: false)
                }
                if let lastExport {
                    activityLine("마지막으로 올림 · \(lastExport.formatted(.relative(presentation: .named)))", emphasized: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityLine(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(emphasized ? CarveColor.ink : CarveColor.secondary)
    }

    /// 받지 못한 것과 올리지 못한 것은 사용자에게 뜻이 다르다.
    private func failureText(_ failure: CloudSyncFailure) -> String {
        switch failure {
        case .accountUnavailable: "iCloud 계정을 확인해 주세요"
        case .accountCheckFailed: "iCloud 계정 상태를 확인하지 못했어요"
        case .importFailed: "iCloud에서 필사를 받아오지 못했어요"
        case .exportFailed: "필사를 iCloud에 올리지 못했어요 · 이 기기에는 저장돼 있어요"
        case .unknown: "동기화 중 문제가 생겼어요"
        }
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    Text("iCloud")
                        .font(CarveTypography.sectionTitle)
                        .foregroundStyle(CarveColor.secondary)

                    // 조작할 수 없는 토글을 켜 둔 채로 보여 주지 않는다. 지금 확인된 계정 상태를 그대로 적는다.
                    accountStatusRow

                    // 계정을 쓸 수 있을 때만 — 계정이 없으면 주고받을 수 없으므로 활동을 말할 것이 없다.
                    if store.availability.canSync {
                        syncActivityRow
                    }

                    CarveDivider()

                    VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
                        Text("필사한 내용을 iCloud로 기기 사이에 동기화해요.")
                            .foregroundStyle(CarveColor.ink)
                        // 동기화를 백업이라고 부르지 않는다 — 지운 것도 함께 전해진다.
                        Text("백업과는 달라요. 한 기기에서 지우면 다른 기기에서도 사라져요.")
                        Text("iCloud 사용 여부는 기기의 설정 앱에서 바꿀 수 있어요.")
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
        .onAppear { send(.onAppear) }
        .onDisappear { send(.onDisappear) }
        // 시안 F2 는 확인 대화상자를 화면 가운데에 띄우고 뒤를 가린다. 팝오버는 버튼에 붙어 한쪽으로 뜨므로
        // 전체를 덮는 표현으로 바꾼다 — 바탕은 `PopupView` 가 직접 그린다.
        .fullScreenCover(item: $store.scope(state: \.path?.popup, action: \.path.popup)) { store in
            PopupView(store: store)
                .presentationBackground(.clear)
        }
    }
    
        
}
