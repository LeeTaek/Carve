//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import ClientInterfaces
import Resources

import ComposableArchitecture
import UIComponents

@ViewAction(for: SettingsFeature.self)
public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsFeature>
    /// 광고 제거를 샀는지. 사이드바 행의 값만 바꾼다.
    @SharedReader(.isAdFree) private var isAdFree: Bool
    /// 고른 화면 모드. 사이드바 행의 값만 바꾼다.
    @SharedReader(.appearanceMode) private var appearanceMode: AppearanceMode

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader(SettingsCatalog.string("설정")) {
                Button {
                    send(.backToCarve)
                } label: {
                    Text("완료", bundle: .module)
                }
                .buttonStyle(.carve(.secondary))
            }

            NavigationSplitView(columnVisibility: .constant(.all)) {
                sideBar
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 320)
            } detail: {
                detailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(maxWidth: 900, maxHeight: 700)
        .carveSurface(
            .panel,
            in: RoundedRectangle(cornerRadius: CarveRadius.panel, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: CarveRadius.panel, style: .continuous))
    }

    private var sideBar: some View {
        // 선택은 경로 상태가 아니라 행으로 비교한다 — 상세 화면의 상태가 바뀌어도 선택 표시가 남는다.
        List(selection: $store.selectedSidebarItem.sending(\.selectSidebarItem)) {
            Section {
                NavigationLink(value: SettingsFeature.SidebarItem.widget) {
                    Text("위젯", bundle: .module)
                }
            } header: {
                Text("필사", bundle: .module)
            }
            Section {
                NavigationLink(value: SettingsFeature.SidebarItem.appearance) {
                    sidebarRow(SettingsCatalog.string("화면 모드"), value: appearanceMode.title)
                }
            } header: {
                Text("화면", bundle: .module)
            }
            Section {
                NavigationLink(value: SettingsFeature.SidebarItem.iCloud) {
                    // 연결 보류 중에는 「보류」 — 이 실행은 이 기기에만 저장한다(정책 §12-6 C14 ③). 까닭은 iCloud 화면이 말한다.
                    sidebarRow("iCloud", value: store.isConnectionHeld ? SettingsCatalog.string("보류") : SettingsCatalog.string("켬"))
                }
                // 확인이 필요한 필기의 지속적인 진입점(정책 §12-6 ④) — 개수는 화면을 열 때 센다.
                NavigationLink(DraftRecoveryCopy.title, value: SettingsFeature.SidebarItem.draftRecovery)
                // 필사 백업 — 백업 만들기 · 불러오기(2.1).
                NavigationLink(BackupCopy.title, value: SettingsFeature.SidebarItem.backup)
            } header: {
                Text("저장", bundle: .module)
            }
            Section {
                NavigationLink(value: SettingsFeature.SidebarItem.help) {
                    Text("도움말", bundle: .module)
                }
                NavigationLink(value: SettingsFeature.SidebarItem.patchnote) {
                    Text("패치노트", bundle: .module)
                }
                NavigationLink(value: SettingsFeature.SidebarItem.sendFeedback) {
                    Text("의견 보내기", bundle: .module)
                }
                NavigationLink(value: SettingsFeature.SidebarItem.appVersion) {
                    sidebarRow(SettingsCatalog.string("앱 버전"), value: UIDevice.appVersion())
                }
            } header: {
                Text("지원", bundle: .module)
            }
            Section {
                // 구매를 권하지 않고 설정에 한 줄로만 둔다(시안 K4).
                NavigationLink(value: SettingsFeature.SidebarItem.removeAds) {
                    sidebarRow(SettingsCatalog.string("광고 제거"), value: isAdFree ? SettingsCatalog.string("구매함") : "")
                }
                if store.isPrivacyOptionsRequired {
                    // 동의가 필요한 지역에서는 광고 동의를 다시 고를 수 있는 진입점을 둬야 한다(UMP 개인정보 옵션).
                    Button {
                        send(.privacyOptionsTapped)
                    } label: {
                        Text("광고 개인정보 옵션", bundle: .module)
                    }
                    .foregroundStyle(CarveColor.ink)
                }
            } header: {
                Text("광고", bundle: .module)
            }
        }
        .onAppear {
            send(.onAppear)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                CarveDivider()
                // 글자로 「가가」 라고 쓰면 무엇을 가리키는지 알기 어려워 헤더의 본문 설정 버튼 모양을 그대로 보여 준다.
                VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                    Text("본문 글꼴·크기·줄 간격은", bundle: .module)
                    HStack(spacing: CarveSpacing.xxSmall) {
                        Text("필사 화면 위", bundle: .module)
                        CarveIconBadge(.textFormat)
                        Text("\(Text("(본문 설정)", bundle: .module).font(.caption2))에서 바꿔요.", bundle: .module)
                    }
                }
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
                .padding(.horizontal, CarveSpacing.small)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("본문 글꼴·크기·줄 간격은 필사 화면 위 본문 설정에서 바꿔요.", bundle: .module))
            }
            .padding(.bottom, CarveSpacing.small)
            .background(CarveColor.surface)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(CarveColor.surface)
        .toolbar(removing: .sidebarToggle)
    }

    private func sidebarRow(_ title: String, value: String) -> some View {
        HStack(spacing: CarveSpacing.small) {
            Text(title)
            Spacer(minLength: 0)
            Text(value)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
        }
    }


    @ViewBuilder
    private func detailView() -> some View {
        switch store.path {
        case .iCloud:
            if let store = store.scope(state: \.path?.iCloud, action: \.path.iCloud) {
                CloudSettingView(store: store)
            }
        case .draftRecovery:
            if let store = store.scope(state: \.path?.draftRecovery, action: \.path.draftRecovery) {
                DraftRecoveryView(store: store)
            }
        case .backup:
            if let store = store.scope(state: \.path?.backup, action: \.path.backup) {
                BackupView(store: store)
            }
        case .widget:
            if let store = store.scope(state: \.path?.widget, action: \.path.widget) {
                WidgetSettingsView(store: store)
            }
        case .appearance:
            if let store = store.scope(state: \.path?.appearance, action: \.path.appearance) {
                AppearanceSettingsView(store: store)
            }
        case .help:
            if let store = store.scope(state: \.path?.help, action: \.path.help) {
                HelpView(store: store)
            }
        case .patchnote:
            if let store = store.scope(state: \.path?.patchnote, action: \.path.patchnote) {
                PatchnoteView(store: store, style: .detail)
            }
        case .sendFeedback:
            if let store = store.scope(state: \.path?.sendFeedback, action: \.path.sendFeedback) {
                SendFeedbackView(store: store)
            }
        case .appVersion:
            if let store = store.scope(state: \.path?.appVersion, action: \.path.appVersion) {
                AppVersionView(store: store)
            }
        case .removeAds:
            if let store = store.scope(state: \.path?.removeAds, action: \.path.removeAds) {
                RemoveAdsView(store: store)
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
