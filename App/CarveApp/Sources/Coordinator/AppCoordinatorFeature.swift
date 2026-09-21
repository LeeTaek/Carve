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
    
    public enum Action {
        case root(PresentationAction<Root.Action>)
        case patchnote(PresentationAction<PatchnoteFeature.Action>)
        case settings(PresentationAction<SettingsFeature.Action>)
        /// Path와 관련된 프레젠테이션 액션.
        case path(StackActionOf<Path>)
        /// 위젯 등 외부에서 앱을 열었다.
        case openedURL(URL)
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

    public var body: some Reducer<State, Action> {
        /// 자식 Feature에서 올라오는 액션을 기반으로 루트 화면 전환을 수행하는 Reducer.
        /// - Note: LaunchProgress의 `.syncCompleted`, Carve의 `.moveToSetting,
        ///         Settings의 `.backToCarve`와 같은 액션을 감지하여 `root`, `path`를 교체한다.
        Reduce { state, action in
            switch action {
            case .root(.presented(.launchProgress(.syncCompleted))):
                // 들어가기 직전에 시작 화면의 상태를 한 번 더 본다 — 막힘 · 재실행 요구로 바뀌었으면 들어가지 않는다 (테스트 계획 MIG-F1).
                // 저장소를 쓸 수 없을 때 앱이 쥔 대체 컨테이너는 저장을 거절하지 않으므로 이 확인이 마지막 경계다.
                guard case .launchProgress(let launch)? = state.root,
                      launch.syncState.launchRoute == .enterWriting else {
                    break
                }
                let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                let previousVersion = state.lastSeenAppVersion
                state.$lastSeenAppVersion.withLock { $0 = currentVersion }
                state.root = .carve(.initialState)
                if let previousVersion, previousVersion != currentVersion {
                    state.patchnote = .initialState
                }
                // 위젯을 눌러 시작했다면 필사 화면이 준비된 지금 그 절로 간다.
                if let verse = state.pendingWidgetVerse {
                    state.pendingWidgetVerse = nil
                    return .send(.root(.presented(.carve(.moveToVerse(verse)))))
                }
                
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

            // 절 메뉴의 「남은 필기 N」 — 설정을 그 자리로 연다(정책 §12-6 ④). 되살리지 않고 보여 주기만 한다.
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
