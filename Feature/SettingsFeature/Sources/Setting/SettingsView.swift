//
//  SettingView.swift
//  Settings
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import Resources

import ComposableArchitecture
import UIComponents

@ViewAction(for: SettingsFeature.self)
public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsFeature>
    
    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader("설정") {
                Button("완료") {
                    send(.backToCarve)
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
        List(selection: $store.path.sending(\.push)) {
            Section("필사") {
                NavigationLink(value: SettingsFeature.Path.State.canvas(.initialState)) {
                    sidebarRow("필사 캔버스", value: "단일")
                }
            }
            Section("저장") {
                NavigationLink(value: SettingsFeature.Path.State.iCloud(.initialState)) {
                    sidebarRow("iCloud", value: "켬")
                }
            }
            Section("지원") {
                NavigationLink("도움말", value: SettingsFeature.Path.State.help(.initialState))
                NavigationLink("패치노트", value: SettingsFeature.Path.State.patchnote(.initialState))
                NavigationLink("의견 보내기", value: SettingsFeature.Path.State.sendFeedback(.initialState))
                NavigationLink(value: SettingsFeature.Path.State.appVersion(.initialState)) {
                    sidebarRow("앱 버전", value: UIDevice.appVersion())
                }
            }
            if store.isPrivacyOptionsRequired {
                // 동의가 필요한 지역에서는 광고 동의를 다시 고를 수 있는 진입점을 둬야 한다(UMP 개인정보 옵션).
                Section("광고") {
                    Button("광고 개인정보 옵션") {
                        send(.privacyOptionsTapped)
                    }
                    .foregroundStyle(CarveColor.ink)
                }
            }
        }
        .onAppear {
            send(.onAppear)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                CarveDivider()
                Text("본문 글꼴·크기·줄 간격은\n필사 화면 위 「가가」에서 바꿔요.")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .padding(.horizontal, CarveSpacing.small)
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
        case .canvas:
            if let store = store.scope(state: \.path?.canvas, action: \.path.canvas) {
                CanvasSettingsView(store: store)
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
