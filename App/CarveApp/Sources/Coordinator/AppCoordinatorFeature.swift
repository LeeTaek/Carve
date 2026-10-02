//
//  AppCoordinatorFeature.swift
//  Carve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import CarveFeature
import ChartFeature
import ClientInterfaces
import SettingsFeature

import ComposableArchitecture

@Reducer
public struct AppCoordinatorFeature: Sendable {
    @ObservableState
    public struct State {
        /// 처음 상태. 차트 · 설정 화면 상태(광고 자리의 `UIView` 등)를 담아 `Sendable` 이 아니므로 저장하지 않고 매번 만든다.
        public static var initialState: Self { Self() }
        /// 보류 중 로그인과 저장소 소유가 확인됐다 — 로딩 없이 재실행을 안내한다(2026-09-28 결정).
        public var showsRelaunchGuidance = false
        /// 이번 실행에서 재실행 안내를 이미 띄웠다. 닫은 뒤 다시 띄우지 않는다 — 설정의 iCloud 화면은 계속 같은 안내를 보인다.
        var didShowRelaunchGuidance = false
        /// iCloud 에 연결된 뒤 가져올 **연결 전 필기** 수 — 있으면 필사 화면 위에 막지 않는 안내를 띄운다(2026-09-29, 실행마다 한 번).
        public var beforeConnectionNotice: Int?
        /// 이번 실행에서 연결 전 필기 안내를 이미 띄웠다. 「나중에」 로 닫으면 다음 실행까지 다시 띄우지 않는다.
        var didShowBeforeConnectionNotice = false
        /// 2.0.x 에서 「필사 캔버스」 를 끄고(절마다 쓰는 캔버스) 쓰던 사용자에게 그 캔버스가 없어졌다고 알리는 막지 않는 안내(2.1 결정 6).
        /// 필사 화면에 처음 들어갈 때 정하고, 어느 버튼으로 닫든 저장된 키를 지워 다시 띄우지 않는다.
        public var showsCanvasRemovalNotice = false
        /// 현재 루트 화면 (트리기반)
        @Presents public var root: Root.State? = .launchProgress(.initialState)
        /// 업데이트 패치노트 표시 상태
        @Presents public var patchnote: PatchnoteFeature.State?
        /// 필사 화면 위에 패널로 표시하는 앱 설정 상태.
        @Presents public var settings: SettingsFeature.State?
        /// 마지막으로 확인한 앱 버전. 값이 없는 기존 설치에는 패치노트를 자동 표시하지 않는다.
        @Shared(.appStorage("lastSeenAppVersion")) public var lastSeenAppVersion: String?
        /// 루트 화면 위에 Push될 화면 Path. (스택 기반)
        public var path: StackState<Path.State> = .init()
        /// 위젯을 눌러 앱이 시작됐을 때 필사 화면이 준비되면 이동할 절.
        var pendingWidgetVerse: BibleVerse?
        /// `-UITestRoute` 로 받은 화면 — 필사 화면이 준비되면(위젯 보류 절과 같은 때) 연다. 실행 인자는 Debug 빌드에서만 읽으므로 Release 에서는 늘 nil 이다.
        var pendingLaunchRoute: UITestRoute?
        // analytics key
        public var currentScreenKey: String {
            if settings != nil {
                return "Settings"
            }

            // Stack top이 있으면 그걸 우선한다.
            if let topPath = path.last {
                switch topPath {
                case .chart:
                    return "Chart"
                case .favorites:
                    return "Favorites"
                }
            }

            // Stack이 비어 있으면 root 기준
            switch root {
            case .some(.launchProgress):
                return "LaunchProgress"
            case .some(.carve):
                return "Carve"
            case .none:
                return "Unknown"
            }
        }
    }
    @Dependency(\.analyticsClient) private var analyticsClient
    /// 지금 앱의 마케팅 버전 — 마지막으로 본 버전과 견주어 패치노트를 띄운다.
    @Dependency(\.appVersion) private var appVersion
    @Dependency(\.legacySeparationHoldState) private var holdState
    @Dependency(\.drawingEditEnvironment) private var editEnvironment
    @Dependency(\.verseDraftRecoveryReader) private var draftReader
    @Dependency(\.drawingRepository) private var drawingRepository
    /// 2.0.x 의 「필사 캔버스」 설정이 남은 `UserDefaults`(앱은 `.standard`) — N-Canvas 제거 안내를 띄울지 읽고, 닫으면 그 키를 지운다.
    @Dependency(\.defaultAppStorage) private var appStorage

    private enum CancelID { case relaunchGuidance, beforeConnection }
    
    public enum Action {
        case root(PresentationAction<Root.Action>)
        case patchnote(PresentationAction<PatchnoteFeature.Action>)
        case settings(PresentationAction<SettingsFeature.Action>)
        /// Path와 관련된 프레젠테이션 액션.
        case path(StackActionOf<Path>)
        /// 위젯 등 외부에서 앱을 열었다.
        case openedURL(URL)
        /// 보류 중 편집 환경을 다시 읽었다 — 재실행하면 연결되는지 본다.
        /// 2.0.0 은 실행 중에 저장소를 다시 연결하지 않는다 — 옛 컨테이너가 해제되지 않아 local-only 로 되돌아갔다(2026-09-28 실측).
        case connectionEnvironmentChanged(DrawingEditEnvironment)
        /// 재실행 안내를 닫았다.
        case relaunchGuidanceDismissed
        /// 동기화 저장소에 쓸 수 있게 됐고, 가져올 연결 전 필기가 있다.
        case beforeConnectionDraftsFound(Int)
        /// 연결 전 필기 안내의 「필기 확인하기」 — 설정의 「확인이 필요한 필기」 를 연다.
        case beforeConnectionNoticeReviewTapped
        /// 연결 전 필기 안내의 「나중에」 — 필기는 그대로 남는다.
        case beforeConnectionNoticeDismissed
        /// N-Canvas 제거 안내의 「의견 보내기」 — 안내를 닫고(키를 지움) 설정의 「의견 보내기」 를 연다.
        case canvasRemovalNoticeFeedbackTapped
        /// N-Canvas 제거 안내의 「확인」 — 안내를 닫고 키를 지운다.
        case canvasRemovalNoticeDismissed
    }
    
    @Reducer
    public enum Root {
        /// CloudKit 동기화/마이그레이션 진행 상태를 표시하는 Launch 화면 흐름.
        case launchProgress(LaunchProgressFeature)
        /// 성경 필사/그리기 메인 흐름을 담당하는 Carve 네비게이션.
        case carve(CarveNavigationFeature)
    }
    
    /// AppCoordinator가 전환할 수 있는 루트 화면들의 집합.
    @Reducer
    public enum Path {
        /// 필사 통계 차트 화면 흐름.
        case chart(DrawingChartFeature)
        /// 즐겨찾기 목록 화면 흐름(시안 N4 · N5).
        case favorites(FavoriteListFeature)
    }
    
    /// 위젯이 넘긴 URL 의 절. 앱이 아는 권이 아니면 nil.
    static func verse(from url: URL) -> BibleVerse? {
        guard let link = VerseWidgetDeepLink.parse(url),
              let title = BibleTitle(rawValue: link.titleRawValue) else { return nil }
        return BibleVerse(title: BibleChapter(title: title, chapter: link.chapter), verse: link.verse, sentence: "")
    }

    /// 보류 중 편집 환경이 바뀔 때마다(로그인 · 앱 활성화) 다시 읽는다. 재실행하면 연결되면 안내하고 구독을 멈춘다.
    private func observeRelaunchGuidance() -> Effect<Action> {
        .run { [editEnvironment] send in
            await send(.connectionEnvironmentChanged(await editEnvironment.current()))
            for await _ in editEnvironment.changes() {
                await send(.connectionEnvironmentChanged(await editEnvironment.current()))
            }
        }
        .cancellable(id: CancelID.relaunchGuidance, cancelInFlight: true)
    }

    /// 이 실행에서 동기화 저장소에 쓸 수 있게 되면(계정 · 소유 확인), 가져오기를 기다리는 **연결 전 필기**를 센다(2026-09-29).
    ///
    /// 계정이 확인됐다는 이유만으로 그 필기를 지금 계정에 넣지 않는다 — 수만 세어 안내하고, 넣기는 사용자가 견주고 고른 절만 한다. 연결을 보류한
    /// 실행(C14)은 이번 실행 동안 쓸 수 없으므로 세지 않는다 — 앱을 다시 열어 연결되면 그때 안내한다.
    private func observeBeforeConnectionDrafts() -> Effect<Action> {
        .run { [editEnvironment, draftReader, drawingRepository] send in
            guard let draftReader else { return }
            // 먼저 구독하고 읽는다 — 읽은 뒤 · 구독 전에 쓸 수 있게 된 것을 놓치지 않는다.
            let changes = editEnvironment.changes()
            var environment = await editEnvironment.current()
            if SyncedWriteBlock.check(environment) != nil {
                guard !environment.connectionHeld else { return }
                var ready = false
                for await _ in changes {
                    environment = await editEnvironment.current()
                    if SyncedWriteBlock.check(environment) == nil {
                        ready = true
                        break
                    }
                }
                guard ready else { return }
            }
            let found = await VerseDraftRecoveryQuery(reader: draftReader, repository: drawingRepository)
                .beforeConnectionCount(environment: environment)
            if found > 0 { await send(.beforeConnectionDraftsFound(found)) }
        }
        .cancellable(id: CancelID.beforeConnection, cancelInFlight: true)
    }

    public var body: some Reducer<State, Action> {
        /// 자식 Feature에서 올라오는 액션을 기반으로 루트 화면 전환을 수행하는 Reducer.
        /// - Note: LaunchProgress의 `.syncCompleted`, Carve의 `.moveToSetting,
        ///         Settings의 `.backToCarve`와 같은 액션을 감지하여 `root`, `path`를 교체한다.
        Reduce { state, action in
            switch action {
            case .root(.presented(.launchProgress(.syncCompleted))):
                // 들어가기 직전에 시작 화면의 상태를 한 번 더 본다 — 막힘 · 재실행 요구로 바뀌었으면 들어가지 않는다 (테스트 계획 MIG-F1).
                // 저장소를 쓸 수 없을 때 앱이 쥔 대체 컨테이너는 저장을 거절하지 않으므로 이 확인이 마지막 경계다. 대기 방식(초기 복원 · 일반)과
                // 「먼저 시작하기」 까지 본다(`LaunchWaitRule`, 정책 §3-1).
                guard case .launchProgress(let launch)? = state.root, launch.route == .enterWriting else {
                    break
                }
                let currentVersion = appVersion
                let previousVersion = state.lastSeenAppVersion
                state.$lastSeenAppVersion.withLock { $0 = currentVersion }
                state.root = .carve(.initialState)
                if let previousVersion, previousVersion != currentVersion {
                    state.patchnote = .initialState
                }
                // 2.0.x 에서 「필사 캔버스」 를 끈 사용자면 그 캔버스가 없어졌다고 한 번 알린다(2.1 결정 6).
                state.showsCanvasRemovalNotice = resolveCanvasRemovalNotice()
                // 보류 중이면 로그인 · 소유가 확인되는지 지켜보다가 재실행을 안내한다. 연결을 기다리는 로딩은 띄우지 않는다.
                // 연결된 실행이면 가져오기를 기다리는 연결 전 필기가 있는지 보고 안내한다(2026-09-29).
                let guidance: Effect<Action> = holdState.isHeld ? observeRelaunchGuidance() : observeBeforeConnectionDrafts()
                // `-UITestRoute`(Debug)로 받은 화면도 같은 때 연다 — 시작 화면(새 설치 복원 대기의 「먼저 시작하기」 포함)이 끝난 뒤다.
                let launchRoute = openPendingLaunchRoute(state: &state)
                // 위젯을 눌러 시작했다면 필사 화면이 준비된 지금 그 절로 간다.
                if let verse = state.pendingWidgetVerse {
                    state.pendingWidgetVerse = nil
                    return .merge(guidance, launchRoute, .send(.root(.presented(.carve(.moveToVerse(verse))))))
                }
                return .merge(guidance, launchRoute)

            case .connectionEnvironmentChanged(let environment):
                guard !state.didShowRelaunchGuidance, environment.connectsOnRelaunch else { break }
                state.didShowRelaunchGuidance = true
                state.showsRelaunchGuidance = true
                return .cancel(id: CancelID.relaunchGuidance)

            case .relaunchGuidanceDismissed:
                state.showsRelaunchGuidance = false

            case .beforeConnectionDraftsFound(let count):
                // 실행마다 한 번 — 「나중에」 로 닫은 뒤 이 실행에서는 다시 띄우지 않는다. 설정 · 절 메뉴로는 언제든 들어간다.
                guard !state.didShowBeforeConnectionNotice else { break }
                state.didShowBeforeConnectionNotice = true
                state.beforeConnectionNotice = count

            case .beforeConnectionNoticeReviewTapped:
                state.beforeConnectionNotice = nil
                state.settings = SettingsFeature.State.initialState(path: .draftRecovery(.initialState))
                return .send(.root(.presented(.carve(.view(.closeNavigationBar)))))

            case .beforeConnectionNoticeDismissed:
                state.beforeConnectionNotice = nil

            case .canvasRemovalNoticeFeedbackTapped:
                dismissCanvasRemovalNotice(state: &state)
                state.settings = SettingsFeature.State.initialState(path: .sendFeedback(.initialState))

            case .canvasRemovalNoticeDismissed:
                dismissCanvasRemovalNotice(state: &state)

            case .openedURL(let url):
                guard let verse = Self.verse(from: url) else { break }
                // 위젯에서 들어왔다 — 설정 · 다른 화면을 닫고 그 절을 연다.
                state.settings = nil
                state.path.removeAll()
                guard case .some(.carve) = state.root else {
                    // 아직 준비 화면이다. 필사 화면이 뜨면 그때 이동한다.
                    state.pendingWidgetVerse = verse
                    break
                }
                return .send(.root(.presented(.carve(.moveToVerse(verse)))))

            case .root(.presented(.carve(.view(.moveToSetting)))):
                state.settings = .initialState

            // 절 메뉴의 「확인이 필요한 필기 N」 · 도착 안내의 「필기 확인하기」 — 설정을 그 자리로 연다(정책 §12-6 ④).
            case .root(.presented(.carve(.scope(.carveDetailAction(
                .scope(.chapterCanvasAction(.delegate(.draftRecoveryRequested)))
            ))))):
                state.settings = SettingsFeature.State.initialState(path: .draftRecovery(.initialState))
                return .send(.root(.presented(.carve(.view(.closeNavigationBar)))))
                
            case .root(.presented(.carve(.view(.moveToChart)))):
                state.path.append(.chart(.initialState))

            case .root(.presented(.carve(.view(.moveToFavorites)))):
                state.path.append(.favorites(.initialState))

            case .settings(.presented(.view(.backToCarve))):
                state.settings = nil

            case .path(.element(id: _, action: .chart(.delegate(.backToWriting)))),
                 .path(.element(id: _, action: .favorites(.delegate(.backToWriting)))):
                state.path.removeLast()
                // 차트 「필사하러 가기」 · 즐겨찾기 「말씀 보러 가기」 는 필사 화면으로 가는 버튼이다 —
                // 탐색 열(사이드바 · 장 목록)을 닫고 필사 화면만 남긴다.
                return .send(.root(.presented(.carve(.view(.closeNavigationBar)))))

            case let .path(.element(id: _, action: .favorites(.delegate(.openVerse(verse))))):
                state.path.removeLast()
                return .send(.root(.presented(.carve(.moveToVerse(verse)))))

            case .path(.element(id: _, action: .favorites(.delegate(.favoritesChanged)))):
                // 목록이 떠 있는 동안 뒤의 필사 화면 표시를 맞춰 둔다 — 시스템 뒤로 가기로 닫혀도 따로 알릴 필요가 없다.
                return .send(.root(.presented(.carve(.refreshFavorites))))

            case .patchnote(.presented(.delegate(.close))):
                state.patchnote = nil

            case .patchnote(.presented(.delegate(.showHelp))):
                state.patchnote = nil
                state.settings = SettingsFeature.State.initialState(path: .help(.initialState))

            case .settings(.presented(.delegate(.restartFirstRunGuide))):
                state.settings = nil
                return .send(.root(.presented(.carve(.view(.restartFirstRunGuide)))))
                
            case let .path(.element(id: _, action: .chart(.drawingWeeklySummary(.openChapter(chapter))))):
                state.path.removeLast()
                return .send(.root(.presented(.carve(.moveToChapter(chapter)))))
                
            case let .path(.element(id: _, action: .chart(.drawingWeeklySummary(.openVerse(verse))))):
                state.path.removeLast()
                return .send(.root(.presented(.carve(.moveToVerse(verse)))))

            default:
                break
            }
            return .none
        }
        .onChange(of: \.currentScreenKey) { _, newScreenKey in
            Reduce { _, _ in
                    .run { _ in
                        analyticsClient.screen(
                            newScreenKey,
                            parameters: [
                                "screen_name": .string(newScreenKey),
                                "screen_class": .string("AppCoordinator")
                            ]
                        )
                    }
            }
        }
        .ifLet(\.$root, action: \.root)
        .ifLet(\.$patchnote, action: \.patchnote) {
            PatchnoteFeature()
        }
        .ifLet(\.$settings, action: \.settings) {
            SettingsFeature()
        }
        .forEach(\.path, action: \.path)
    }
}

// MARK: - N-Canvas 제거 안내 (2.1 결정 6)

extension AppCoordinatorFeature {
    /// 2.0.x 의 「필사 캔버스」 설정이 쓰던 `UserDefaults` 키. 2.1 은 이 값을 읽는 곳이 없고, 안내를 정할 때만 본다.
    enum CanvasRemovalNotice {
        /// 「단일 캔버스 사용」 토글 값. Bool false 로 남아 있으면 그 사용자는 절마다 쓰는 캔버스(N-Canvas)로 쓰고 있었다.
        static let singleCanvasEnabledKey = "singleCanvasEnabled"
        /// 2.0.x 가 토글 값을 설치당 한 번 지웠는지 적던 키 — 함께 지운다.
        static let storedValueResetKey = "singleCanvasStoredValueReset"
    }

    /// 필사 화면에 들어갈 때 N-Canvas 제거 안내를 띄울지 정한다.
    ///
    /// - 입력: `appStorage` 의 `singleCanvasEnabled`. 2.0.0(Xcode 27 빌드)이 JSON 으로 쓴 값은 앱 시작 때 `AppStorageFormatMigration` 이 Bool 로 되돌려 둔다.
    /// - 출력: 그 값이 Bool false 로 저장돼 있으면 true(안내를 띄운다 — 키는 버튼을 누를 때 지운다).
    /// - 부작용: 키가 없거나 false 가 아니면 안내 없이 두 키를 곧바로 지운다 — 읽는 곳이 없는 값이다.
    private func resolveCanvasRemovalNotice() -> Bool {
        if appStorage.object(forKey: CanvasRemovalNotice.singleCanvasEnabledKey) as? Bool == false {
            return true
        }
        removeCanvasRemovalKeys()
        return false
    }

    /// N-Canvas 제거 안내를 닫는다. 입력: 코디네이터 상태. 부작용: 두 키를 지워 다음 실행에서도 다시 띄우지 않는다.
    private func dismissCanvasRemovalNotice(state: inout State) {
        state.showsCanvasRemovalNotice = false
        removeCanvasRemovalKeys()
    }

    /// 2.0.x 「필사 캔버스」 설정의 두 키를 지운다. 부작용: `appStorage` 에서 키를 지운다(없으면 아무것도 바뀌지 않는다).
    private func removeCanvasRemovalKeys() {
        appStorage.removeObject(forKey: CanvasRemovalNotice.singleCanvasEnabledKey)
        appStorage.removeObject(forKey: CanvasRemovalNotice.storedValueResetKey)
    }
}

// MARK: - 화면 바로 열기 (`-UITestRoute`)

extension AppCoordinatorFeature {
    /// `-UITestRoute <경로>` 가 여는 화면. UI 테스트 · 시뮬레이터 확인이 탭 단계 없이 그 화면에서 시작한다.
    ///
    /// 앱 진입점이 Debug 빌드에서만 실행 인자를 한 번 읽어(`parse`) `State.pendingLaunchRoute` 에 넣고, 시작 화면이 끝나 필사 화면에 들어간 직후
    /// (위젯 보류 절과 같은 때) 연다. 시작 화면 — 새 설치 복원 대기의 「먼저 시작하기」 — 은 건너뛰지 않는다.
    ///
    /// | 경로 | 여는 화면 |
    /// |---|---|
    /// | `navigation` | 성경 탐색 — 헤더 제목을 누른 것처럼 탐색 열을 모두 연다 |
    /// | `chart` · `favorites` | 기록 차트 · 즐겨찾기 목록을 필사 화면 위에 쌓는다 |
    /// | `settings` | 설정의 첫 화면(iCloud) |
    /// | `settings/<하위>` | 설정의 그 화면 — `icloud` · `draftRecovery` · `widget` · `appearance` · `help` · `patchnote` · `sendFeedback` · `appVersion` · `removeAds` |
    /// | `verse/<절 번호>` | 시작 장(`-UITestChapter` 또는 마지막으로 연 장)의 그 절 |
    ///
    /// 이름은 대소문자를 가리지 않는다. 모르는 경로는 로그만 남기고 무시한다 — 앱은 경로 없이 시작한다.
    enum UITestRoute: Equatable, Sendable {
        case navigation
        case chart
        case favorites
        /// 설정. nil 이면 설정의 첫 화면이다.
        case settings(SettingsFeature.SidebarItem?)
        /// 시작 장의 절 번호(1 이상).
        case verse(Int)

        /// 경로 문자열을 읽는다. 모르는 경로 · 설정 하위 이름이나 1 보다 작은 절 번호면 nil.
        init?(_ value: String) {
            let parts = value.lowercased().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            switch parts {
            case ["navigation"]: self = .navigation
            case ["chart"]: self = .chart
            case ["favorites"]: self = .favorites
            case ["settings"]: self = .settings(nil)
            default:
                guard parts.count == 2 else { return nil }
                if parts[0] == "settings",
                   let item = SettingsFeature.SidebarItem.allCases.first(where: { $0.routeName.lowercased() == parts[1] }) {
                    self = .settings(item)
                } else if parts[0] == "verse", let verse = Int(parts[1]), verse > 0 {
                    self = .verse(verse)
                } else {
                    return nil
                }
            }
        }
    }

    /// `-UITestRoute` 로 받은 화면을 연다. 필사 화면(`root == .carve`)에 막 들어간 때 부르고, 받은 경로가 없으면 아무것도 하지 않는다.
    private func openPendingLaunchRoute(state: inout State) -> Effect<Action> {
        guard let route = state.pendingLaunchRoute else { return .none }
        state.pendingLaunchRoute = nil
        switch route {
        case .navigation:
            // 헤더 제목을 누른 것과 같다 — 탐색 열을 모두 열고 현재 장을 고른 목록으로 시작한다. 서재 버튼은 열고 닫기를 바꾸므로 쓰지 않는다.
            return .send(.root(.presented(.carve(.scope(.carveDetailAction(.scope(.headerAction(.view(.titleDidTapped)))))))))
        case .chart:
            state.path.append(.chart(.initialState))
        case .favorites:
            state.path.append(.favorites(.initialState))
        case .settings(let item):
            state.settings = item.map { SettingsFeature.State.initialState(path: $0.routePath) } ?? .initialState
        case .verse(let verse):
            // 장은 시작 장(`-UITestChapter` 또는 마지막으로 연 장)이다. 위젯 절처럼 본문 없이 보낸다.
            guard case .carve(let carve)? = state.root else { return .none }
            return .send(.root(.presented(.carve(.moveToVerse(BibleVerse(title: carve.currentTitle, verse: verse, sentence: ""))))))
        }
        return .none
    }
}

private extension SettingsFeature.SidebarItem {
    /// `-UITestRoute settings/<이름>` 의 이름.
    var routeName: String {
        switch self {
        case .iCloud: "icloud"
        case .draftRecovery: "draftRecovery"
        case .widget: "widget"
        case .appearance: "appearance"
        case .help: "help"
        case .patchnote: "patchnote"
        case .sendFeedback: "sendFeedback"
        case .appVersion: "appVersion"
        case .removeAds: "removeAds"
        }
    }

    /// 이 행이 여는 화면의 처음 상태. `SettingsFeature` 의 같은 표(`initialPath`)는 모듈 밖에 보이지 않아 여기에 다시 둔다.
    var routePath: SettingsFeature.Path.State {
        switch self {
        case .iCloud: .iCloud(.initialState)
        case .draftRecovery: .draftRecovery(.initialState)
        case .widget: .widget(.initialState)
        case .appearance: .appearance(.initialState)
        case .help: .help(.initialState)
        case .patchnote: .patchnote(.initialState)
        case .sendFeedback: .sendFeedback(.initialState)
        case .appVersion: .appVersion(.initialState)
        case .removeAds: .removeAds(.initialState)
        }
    }
}

#if DEBUG
extension AppCoordinatorFeature.UITestRoute {
    /// 실행 인자에서 경로를 읽는다(Debug 전용). 인자가 없으면 nil 이고, 값이 없거나 모르는 경로면 로그만 남기고 nil 이다 — 앱은 경로 없이 시작한다.
    static func parse(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: LaunchArgument.uiTestRoute) else { return nil }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        guard let route = Self(value) else {
            Log.info("UITEST 화면 경로를 읽지 못해 무시함", value)
            return nil
        }
        Log.info("UITEST 화면 경로", value)
        return route
    }
}

extension AppCoordinatorFeature {
    /// 억제 스위치를 저장한다(Debug 전용). 앱 진입점이 Store 를 만들기 전에 한 번 부른다 — `UITestLaunchChapter` 와 같은 방식이다.
    ///
    /// - `-UITestSkipFirstRunGuide`: 필사 화면(`CarveNavigationFeature`)과 같은 `@Shared(.appStorage("hasSeenFirstRunGuide"))` 를 true 로 쓴다.
    /// - `-UITestSkipPatchnote`: **앞서 들어간 설치**의 `lastSeenAppVersion` 만 지금 버전으로 바꾼다. 비어 있는 새 설치는 원래 패치노트를 띄우지 않고,
    ///   시작 화면이 같은 값으로 새 설치(복원 대기 · 「먼저 시작하기」)를 가리므로 그대로 둔다.
    static func applyLaunchSuppression(arguments: [String], appVersion: String) {
        if arguments.contains(LaunchArgument.uiTestSkipFirstRunGuide) {
            @Shared(.appStorage("hasSeenFirstRunGuide")) var hasSeenFirstRunGuide = false
            $hasSeenFirstRunGuide.withLock { $0 = true }
            Log.info("UITEST 첫 실행 안내 억제")
        }
        if arguments.contains(LaunchArgument.uiTestSkipPatchnote) {
            @Shared(.appStorage("lastSeenAppVersion")) var lastSeenAppVersion: String?
            if lastSeenAppVersion != nil {
                $lastSeenAppVersion.withLock { $0 = appVersion }
            }
            Log.info("UITEST 패치노트 억제", appVersion)
        }
    }
}
#endif
