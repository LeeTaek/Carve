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
    /// 이 실행에서 앱 안에서 바꾼 화면 언어. 사이드바 「언어」 행의 값만 바꾼다.
    @SharedReader(.appLanguageOverride) private var languageOverride: AppLanguage?
    /// 화면 언어 — 미리 만드는 문구(패널 제목 · 행 이름 · 값)를 이 언어로 만든다(즉시 전환 단계 2 · 3).
    @Environment(\.locale) private var locale
    /// 글자 크기. 접근성 크기에서는 사이드바 바닥글을 고정하지 않고 목록 끝에 둔다.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader(SettingsCatalog.string("설정", locale: locale)) {
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
                    sidebarRow(.appearance, title: SettingsCatalog.string("화면 모드", locale: locale), value: appearanceMode.title(locale: locale))
                }
                // 앱 안에서 고르면 바로 그 언어를 보인다. 설정 앱에서 바꾸면 iOS 가 앱을 다시 시작한 뒤의 언어다(시작 때 언어).
                NavigationLink(value: SettingsFeature.SidebarItem.language) {
                    sidebarRow(.language, title: SettingsCatalog.string("언어", locale: locale), value: (languageOverride ?? .launch).nativeName)
                }
            } header: {
                Text("화면", bundle: .module)
            }
            Section {
                NavigationLink(value: SettingsFeature.SidebarItem.iCloud) {
                    // 연결 보류 중에는 「보류」 — 이 실행은 이 기기에만 저장한다(정책 §12-6 C14 ③). 까닭은 iCloud 화면이 말한다.
                    sidebarRow(
                        .iCloud,
                        title: "iCloud",
                        value: store.isConnectionHeld ? SettingsCatalog.string("보류", locale: locale) : SettingsCatalog.string("켬", locale: locale)
                    )
                }
                // 확인이 필요한 필기의 지속적인 진입점(정책 §12-6 ④) — 개수는 화면을 열 때 센다.
                NavigationLink(DraftRecoveryCopy.title(locale: locale), value: SettingsFeature.SidebarItem.draftRecovery)
                // 필사 백업 — 백업 만들기 · 불러오기(2.1).
                NavigationLink(BackupCopy.title(locale: locale), value: SettingsFeature.SidebarItem.backup)
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
                    sidebarRow(.appVersion, title: SettingsCatalog.string("앱 버전", locale: locale), value: UIDevice.appVersion())
                }
            } header: {
                Text("지원", bundle: .module)
            }
            Section {
                // 구매를 권하지 않고 설정에 한 줄로만 둔다(시안 K4).
                NavigationLink(value: SettingsFeature.SidebarItem.removeAds) {
                    sidebarRow(.removeAds, title: SettingsCatalog.string("광고 제거", locale: locale), value: isAdFree ? SettingsCatalog.string("구매함", locale: locale) : "")
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
            // 접근성 크기에서는 바닥글이 사이드바 절반을 덮었다(2026-10-13) — 고정하지 않고 목록 끝에서 함께 스크롤한다.
            if dynamicTypeSize.isAccessibilitySize {
                Section {
                    textSettingsHint
                        .listRowBackground(Color.clear)
                }
            }
        }
        .onAppear {
            send(.onAppear)
        }
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                    CarveDivider()
                    textSettingsHint
                        .padding(.horizontal, CarveSpacing.small)
                }
                .padding(.bottom, CarveSpacing.small)
                .background(CarveColor.surface)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(CarveColor.surface)
        .toolbar(removing: .sidebarToggle)
    }

    private func sidebarRow(_ item: SettingsFeature.SidebarItem, title: String, value: String) -> some View {
        SettingsSidebarValueRow(title: title, value: value, isSelected: store.selectedSidebarItem == item)
    }

    /// 본문 설정이 어디 있는지 알리는 바닥글(시안 F). 글자로 「가가」 라고 쓰면 무엇을 가리키는지 알기 어려워 헤더의 본문 설정 버튼 모양을 그대로 보여 준다.
    ///
    /// 둘째 줄은 표식을 문장 안에 넣어 한 문단으로 흐르게 한다 — 표식 옆에 문장을 따로 두면 영어가 「with the writing / screen's」 처럼
    /// 표식 왼쪽의 좁은 칸에서 갈라졌다(2026-10-13). 문장 조각은 원래 카탈로그 키 그대로이고, 잇는 보간(`%@ %@ %@`)은 번역하지 않는다.
    private var textSettingsHint: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            Text("본문 글꼴·크기·줄 간격은", bundle: .module)
            CarveIconBadgeInlineParagraph(.textFormat) { badge in
                Text(
                    "\(Text("필사 화면 위", bundle: .module)) \(badge) \(Text("\(Text(verbatim: textSettingsButtonName).font(.caption2))에서 바꿔요.", bundle: .module))",
                    bundle: .module,
                    comment: "번역하지 않음 — 설정 사이드바 바닥글 둘째 줄의 문장 조각과 본문 설정 표식을 한 문단으로 잇는 보간"
                )
            }
        }
        .font(CarveTypography.caption)
        .foregroundStyle(CarveColor.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("본문 글꼴·크기·줄 간격은 필사 화면 위 본문 설정에서 바꿔요.", bundle: .module))
    }

    /// 「(본문 설정)」 · 「(Text Settings)」 — 버튼 이름이 두 줄로 갈라지지 않게 안의 빈칸을 줄바꿈 없는 빈칸으로 바꾼다.
    private var textSettingsButtonName: String {
        SettingsCatalog.string("(본문 설정)", locale: locale).replacingOccurrences(of: " ", with: "\u{00A0}")
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
        case .language:
            if let store = store.scope(state: \.path?.language, action: \.path.language) {
                LanguageSettingsView(store: store)
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

/// 사이드바 행 — 이름과 오른쪽 값(「화면 모드 · 시스템 설정」).
///
/// - 접근성 크기에서는 값을 이름 아래로 내린다. 한 줄에 둘을 두면 사이드바 폭에서 이름과 값이 단어 중간에서 갈라졌다(「Ap-pear-」 · 「Sys-」, 2026-10-13).
/// - iPadOS 17 사이드바는 고른 행을 강조색으로 칠하고 행 글자를 희게 뒤집는다. 그 위에서 보조 색은 거의 보이지 않아(17.5 「언어 · 한국어」)
///   17 에서 고른 행의 값은 행 글자색(`.foreground`)을 따른다 — 강조가 풀린 회색 선택에서는 진한 글자로 함께 바뀐다. 18 · 26 은 흰 · 옅은 선택 바탕에
///   강조색 이름이라 그대로 보조 색이다. 17.5 의 고른 행은 `backgroundProminence` 가 `.standard` 라 그 값으로는 가를 수 없다(2026-10-15 확인).
private struct SettingsSidebarValueRow: View {
    let title: String
    let value: String
    /// 사이드바에서 고른 행인가 — 경로 상태가 아니라 행으로 비교한 선택(`SettingsFeature.State.selectedSidebarItem`).
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: CarveSpacing.xxSmall))
            : AnyLayout(HStackLayout(spacing: CarveSpacing.small))
        layout {
            Text(title)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            // 값이 없는 행(광고 제거 · 사지 않음)은 세로로 쌓을 때 빈 줄을 남기지 않는다.
            if !value.isEmpty {
                Text(value)
                    .font(CarveTypography.caption)
                    .foregroundStyle(valueStyle)
            }
        }
    }

    private var valueStyle: AnyShapeStyle {
        if #available(iOS 18.0, *) {
            return AnyShapeStyle(CarveColor.secondary)
        }
        return isSelected ? AnyShapeStyle(.foreground) : AnyShapeStyle(CarveColor.secondary)
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SettingsFeature()
    }
    SettingsView(store: store)
}
