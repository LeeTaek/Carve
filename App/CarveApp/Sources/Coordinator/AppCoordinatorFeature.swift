//
//  AppCoordinatorFeature.swift
//  Carve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI
import CarveFeature
import ChartFeature
import ClientInterfaces
import SettingsFeature

import ComposableArchitecture

@Reducer
public struct AppCoordinatorFeature {
    @ObservableState
    public struct State {
        public static var initialState = Self()
        /// 보류 중 로그인과 저장소 소유가 확인됐다 — 로딩 없이 재실행을 안내한다(2026-09-28 결정).
        public var showsRelaunchGuidance = false
        /// 이번 실행에서 재실행 안내를 이미 띄웠다. 닫은 뒤 다시 띄우지 않는다 — 설정의 iCloud 화면은 계속 같은 안내를 보인다.
        var didShowRelaunchGuidance = false
        /// iCloud 에 연결된 뒤 가져올 **연결 전 필기** 수 — 있으면 필사 화면 위에 막지 않는 안내를 띄운다(2026-09-29, 실행마다 한 번).
        public var beforeConnectionNotice: Int?
        /// 이번 실행에서 연결 전 필기 안내를 이미 띄웠다. 「나중에」 로 닫으면 다음 실행까지 다시 띄우지 않는다.
        var didShowBeforeConnectionNotice = false
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
    @Dependency(\.legacySeparationHoldState) private var holdState
    @Dependency(\.drawingEditEnvironment) private var editEnvironment
    @Dependency(\.verseDraftRecoveryReader) private var draftReader
    @Dependency(\.drawingRepository) private var drawingRepository

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
                let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                let previousVersion = state.lastSeenAppVersion
                state.$lastSeenAppVersion.withLock { $0 = currentVersion }
                state.root = .carve(.initialState)
                if let previousVersion, previousVersion != currentVersion {
                    state.patchnote = .initialState
                }
                // 보류 중이면 로그인 · 소유가 확인되는지 지켜보다가 재실행을 안내한다. 연결을 기다리는 로딩은 띄우지 않는다.
                // 연결된 실행이면 가져오기를 기다리는 연결 전 필기가 있는지 보고 안내한다(2026-09-29).
                let guidance: Effect<Action> = holdState.isHeld ? observeRelaunchGuidance() : observeBeforeConnectionDrafts()
                // 위젯을 눌러 시작했다면 필사 화면이 준비된 지금 그 절로 간다.
                if let verse = state.pendingWidgetVerse {
                    state.pendingWidgetVerse = nil
                    return .merge(guidance, .send(.root(.presented(.carve(.moveToVerse(verse))))))
                }
                return guidance

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
