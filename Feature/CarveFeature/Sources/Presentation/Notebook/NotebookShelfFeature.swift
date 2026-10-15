//
//  NotebookShelfFeature.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

/// 책장 — 필사책을 고르고 관리하는 화면(2.2 회차별 필사책, 설계 `docs/notebook-design.md` §6-1).
///
/// 차트 · 즐겨찾기처럼 앱 스택에 올라간다(`AppCoordinatorFeature.Path.notebooks`). 진입은 서재 열 아래 아이콘 줄의 「책장」 ·
/// 번역본 팝오버의 「책장 열기」 · 실행 인자 `-UITestRoute notebooks` 다. 다른 화면으로 가는 일은 위임(`Delegate`)으로만 알리고,
/// 코디네이터가 path 와 필사 화면(`CarveNavigationFeature.switchNotebook`)을 바꾼다.
///
/// 지금은 화면 경계만 있다 — 카드 격자 · 만들기 · 이름 바꾸기 · 완료 표시 · 지우기 · 옛 기기 안내는 아직 없다.
@Reducer
public struct NotebookShelfFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Equatable, Sendable {
        public static let initialState = Self()

        public init() { }
    }

    public enum Action: ViewAction {
        case view(View)
        case delegate(Delegate)

        @CasePathable
        public enum View {
            /// 책장이 화면에 나타났다.
            case onAppear
            /// 뒤로 버튼을 눌렀다 — 필사 화면으로 돌아간다.
            case backTapped
        }

        @CasePathable
        public enum Delegate {
            /// 필사책을 골랐다 — 코디네이터가 책장을 닫고 필사 화면을 그 필사책으로 바꾼다.
            case notebookChosen(NotebookID)
            /// 책장에 머문 채 지금 필사책이 바뀌었다(지금 필사책을 지워 기본 필사책으로 돌아갈 때) — 코디네이터가 책장은 둔 채 필사 화면만 바꾼다.
            case currentNotebookChanged(NotebookID)
            /// 필사 화면으로 돌아간다 — 코디네이터가 책장을 닫는다.
            case backToWriting
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.onAppear):
                return .none

            case .view(.backTapped):
                return .send(.delegate(.backToWriting))

            case .delegate:
                return .none
            }
        }
    }
}
