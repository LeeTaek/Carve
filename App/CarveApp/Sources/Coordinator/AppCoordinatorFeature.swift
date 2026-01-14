//
//  AppCoordinatorFeature.swift
//  Carve
//
//  Created by 이택성 on 5/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import CarveFeature
import SettingsFeature
import ChartFeature

import ComposableArchitecture

@Reducer
public struct AppCoordinatorFeature {
    @ObservableState
    public struct State {
        public static var initialState = Self()
        /// 현재 루트 화면 (트리기반)
        @Presents public var root: Root.State? = .launchProgress(.initialState)
        /// 루트 화면 위에 Push될 화면 Path. (스택 기반)
        public var path: StackState<Path.State> = .init()
    }
    public enum Action {
        case root(PresentationAction<Root.Action>)
        /// Path와 관련된 프레젠테이션 액션.
        case path(StackActionOf<Path>)
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
        /// 앱 설정 화면 흐름.
        case settings(SettingsFeature)
        case chart(DrawingChartFeature)
    }
    
    public var body: some Reducer<State, Action> {
        /// 자식 Feature에서 올라오는 액션을 기반으로 루트 화면 전환을 수행하는 Reducer.
        /// - Note: LaunchProgress의 `.syncCompleted`, Carve의 `.moveToSetting,
        ///         Settings의 `.backToCarve`와 같은 액션을 감지하여 `root`, `path`를 교체한다.
        Reduce { state, action in
            switch action {
            case .root(.presented(.launchProgress(.syncCompleted))):
                state.root = .carve(.initialState)
                
            case .root(.presented(.carve(.view(.moveToSetting)))):
                state.path.append(.settings(.initialState))

            case .path(.element(id: _, action: .settings(.view(.backToCarve)))):
                state.path.removeLast()
                
            case let .path(.element(id: _, action: .chart(.drawingWeeklySummary(.openChapter(chapter))))):
                state.path.removeLast()
                return .send(.root(.presented(.carve(.moveToChapter(chapter)))))
                
            case let .path(.element(id: _, action: .chart(.drawingWeeklySummary(.openVerse(verse))))):
              state.path.removeLast()
              return .send(.root(.presented(.carve(.moveToVerse(verse)))))
                
            case .root(.presented(.carve(.view(.moveToChart)))):
                state.path.append(.chart(.initialState))
                
            default:
                break
            }
            return .none
        }
        .ifLet(\.$root, action: \.root)
        .forEach(\.path, action: \.path)
    }
}
