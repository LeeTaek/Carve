//
//  AppCoordinatorView.swift
//  Carve
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveFeature
import ChartFeature
import ClientInterfaces
import Combine
import SettingsFeature
import SwiftUI
import UIComponents

import ComposableArchitecture

/// AppCoordinatorFeature와 연결된 루트 코디네이터 View.
/// - Note: RootView는 트리 기반 네비게이션으로,
///  Settings / Charts(예정) 은 Stack 기반 네비게이션으로 구현.
public struct AppCoordinatorView: View {
    @Bindable private var store: StoreOf<AppCoordinatorFeature>
    /// 설정 > 화면 모드에서 고른 값. 설정 화면이 쓰고 여기서는 읽기만 한다.
    @SharedReader(.appearanceMode) private var appearanceMode: AppearanceMode
    
    public init(store: StoreOf<AppCoordinatorFeature>) {
        self.store = store
    }
    
    /// TCA Path 상태에 따라 Launch/Carve/Settings 중 하나의 화면을 선택적으로 렌더링.
    public var body: some View {
        NavigationStack(
          path: $store.scope(state: \.path, action: \.path)
        ) {
            // RootView 설정 - Tree 기반
            switch store.root {
            case .launchProgress:
                if let store = store.scope(
                    state: \.root?.launchProgress,
                    action: \.root.launchProgress
                ) {
                    LaunchProgressView(store: store)
                }
            case .carve:
                if let store = store.scope(
                    state: \.root?.carve,
                    action: \.root.carve
                ) {
                    CarveNavigationView(store: store)
                }
            default:
                fatalError("RootView init failed")
            }
        } destination: { store in
            // push destination - Stack 기반
            switch store.case {
            case .chart(let store):
                DrawingChartView(store: store)
            case .favorites(let store):
                FavoriteListView(store: store)
            }
        }
        .allowsHitTesting(store.patchnote == nil && store.settings == nil)
        .accessibilityHidden(store.patchnote != nil || store.settings != nil)
        .overlay {
            if let settingsStore = store.scope(state: \.settings, action: \.settings.presented) {
                ZStack {
                    CarveColor.scrim
                        .ignoresSafeArea()
                    SettingsView(store: settingsStore)
                        .padding(60)
                }
            }
        }
        .overlay {
            if let patchnoteStore = store.scope(state: \.patchnote, action: \.patchnote.presented) {
                PatchnoteView(store: patchnoteStore)
            }
        }
        .overlay {
            if store.showsRelaunchGuidance {
                // 로그인 완료와 연결 완료를 구분한다 — 이 실행은 계속 이 기기에만 저장한다. 기다릴 것이 없으므로 로딩을 띄우지 않는다.
                VStack(spacing: 16) {
                    Text("iCloud 로그인을 확인했어요", bundle: .main, comment: "재실행 안내 카드 제목 — iCloud 로그인은 됐다")
                    Text(
                        "아직 이 기기의 필사는 iCloud와 연결되지 않았어요.\n\(CloudSettingsFeature.relaunchToConnect)",
                        bundle: .main,
                        comment: "재실행 안내 카드 본문 — %@ 는 설정의 「앱을 다시 열어 연결」 안내 문장"
                    )
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    Button {
                        store.send(.relaunchGuidanceDismissed)
                    } label: {
                        Text("확인", bundle: .main, comment: "안내 카드 닫기")
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("relaunchGuidance")
            }
        }
        .overlay {
            // 연결 전에 쓴 필기가 있다 — 막지 않고 한 번 알린다. 넣기는 설정에서 절마다 견주고 고른 것만 한다(2026-09-29).
            if store.beforeConnectionNotice != nil, store.patchnote == nil, store.settings == nil, !store.showsRelaunchGuidance {
                VStack(spacing: 16) {
                    Text("iCloud에 연결하기 전에 이 iPad에서 쓴 필기가 있어요", bundle: .main, comment: "연결 전 필기 안내 카드 제목")
                    Text("현재 필사에 넣을 내용을 확인해 주세요.", bundle: .main, comment: "연결 전 필기 안내 카드 본문")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button {
                            store.send(.beforeConnectionNoticeDismissed)
                        } label: {
                            Text("나중에", bundle: .main, comment: "연결 전 필기 안내 — 미룬다")
                        }
                        Button {
                            store.send(.beforeConnectionNoticeReviewTapped)
                        } label: {
                            Text("필기 확인하기", bundle: .main, comment: "연결 전 필기 안내 — 설정의 확인이 필요한 필기로 간다")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("beforeConnectionNotice")
            }
        }
        .overlay {
            // 2.0.x 에서 절마다 쓰는 캔버스로 쓰던 사용자 — 그 캔버스가 없어졌다고 막지 않고 한 번 알린다(2.1 결정 6).
            // 연결 전 필기 안내와 같은 규칙으로 미루고, 두 카드가 겹치지 않게 연결 전 필기 안내가 떠 있는 동안에도 미룬다.
            if store.showsCanvasRemovalNotice, store.patchnote == nil, store.settings == nil, !store.showsRelaunchGuidance,
               store.beforeConnectionNotice == nil {
                VStack(spacing: 16) {
                    Text("절마다 쓰는 캔버스는 이번 버전에서 없어졌어요", bundle: .main, comment: "2.0.x 절마다 캔버스 사용자에게 한 번 보이는 안내 제목")
                    Text("그동안 쓴 필사는 그대로예요. 불편한 점이 있으면 알려 주세요.", bundle: .main, comment: "절마다 캔버스 제거 안내 본문")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button {
                            store.send(.canvasRemovalNoticeFeedbackTapped)
                        } label: {
                            Text("의견 보내기", bundle: .main, comment: "절마다 캔버스 제거 안내 — 의견 보내기 화면으로 간다")
                        }
                        Button {
                            store.send(.canvasRemovalNoticeDismissed)
                        } label: {
                            Text("확인", bundle: .main, comment: "안내 카드 닫기")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvasRemovalNotice")
            }
        }
        // 이 창의 오버레이 · 팝오버까지 같은 모드를 따른다. 필사 영역은 모드와 무관하게 라이트로 그린다(결정 8-1 안 1).
        .preferredColorScheme(appearanceMode.colorScheme)
        // 설정 › 화면 › 언어에서 고른 언어를 이 창 전체에 내려보낸다 — 앱을 다시 시작하지 않고 바로 바뀐다(보관함 「Carve 앱 언어 즉시 전환」).
        .modifier(AppLanguageEnvironment())
    }
}

/// 앱 안에서 고른 화면 언어를 환경 `locale` 로 내려보낸다.
///
/// 고른 적이 없으면 기기 · 앱별 언어(`autoupdatingCurrent`)를 그대로 쓴다. 고른 뒤에는 그 언어로 바꾼 locale 이다 — 지역 · 시간제는 기기 것을 둔다.
/// 규칙은 리듀서 · effect · 인프라가 쓰는 `AppLanguage.displayLocale()` 하나다 — 화면 문구와 리듀서가 만든 문구가 같은 언어가 된다.
/// 수식어는 늘 같은 자리에 둔다 — 조건에 따라 붙였다 떼면 화면 identity 가 바뀌어 필사 화면이 장을 다시 읽는다(onAppear → 캔버스 load).
private struct AppLanguageEnvironment: ViewModifier {
    /// 고른 언어 — body 가 읽어 관찰하려고 둔다(iOS 17+ 는 body 에서 읽은 공유 값이 바뀔 때 다시 그린다). 지우면 언어를 골라도 화면이 그대로다.
    /// 값은 `AppLanguage.displayLocale()` 이 같은 키에서 읽는다.
    @SharedReader(.appLanguageOverride) private var languageOverride: AppLanguage?
    /// 기기의 지역 · 시간제 설정이 바뀐 횟수. 바뀌면 고른 언어의 locale 을 새 설정으로 다시 만든다.
    @State private var localeRevision = 0

    func body(content: Content) -> some View {
        content
            .environment(\.locale, effectiveLocale(revision: localeRevision))
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                localeRevision += 1
            }
    }

    /// 역할: 이 창의 환경 locale 을 만든다 — 리듀서 · effect · 인프라와 같은 `AppLanguage.displayLocale()` 을 쓴다.
    /// 입력 · 출력: 지역 설정 변경 횟수(값은 쓰지 않고 지역 설정 변경을 body 의 의존으로 삼으려고 받는다) → 지금 화면 언어의 locale.
    /// 부작용: 없음. 고른 언어 프로퍼티를 읽기만 해 body 의 의존으로 삼는다 — 값은 `displayLocale()` 이 쓴다.
    private func effectiveLocale(revision _: Int) -> Locale {
        _ = languageOverride
        return AppLanguage.displayLocale()
    }
}

private extension AppearanceMode {
    /// `nil` 이면 기기의 라이트 · 다크 설정을 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
