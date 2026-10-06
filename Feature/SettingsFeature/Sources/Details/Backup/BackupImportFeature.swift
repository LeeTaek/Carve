//
//  BackupImportFeature.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 불러오기」 시트 — 파일 고르기 · 암호 · 검사 · 미리보기 · 적용(설계 docs/backup-import-design.md §4).
//

import Foundation

import ComposableArchitecture

/// 「백업 불러오기」 시트의 자리. 지금은 빈 골격이다 — 흐름(파일 고르기 · 검사 · 미리보기 · 쓰기 게이트 · 적용 · 이어 하기)은 다음 작업이 채운다.
///
/// - `BackupFeature` 가 「불러오기」 를 누르면 `State()` 로 시트를 연다 — 인자 없는 `init()` 을 남긴다.
/// - 시트는 `BackupFeature` 의 `@Presents` 다. 닫기는 이 Feature 안에서 `@Dependency(\.dismiss)` 로 한다(부모를 고치지 않는다).
/// - 검사 · 미리보기 · 불러오기는 구매 여부를 묻지 않는다(정책 §6-4).
@Reducer
public struct BackupImportFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        public init() { }
    }

    public enum Action: ViewAction {
        case view(View)

        /// 화면 사건 — 흐름을 채울 때 더한다.
        public enum View: Sendable {
            /// 시트가 나타났다.
            case onAppear
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.onAppear):
                return .none
            }
        }
    }
}
