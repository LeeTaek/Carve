//
//  BackupFeature.swift
//  SettingsFeature
//
//  설정 → 「필사 백업」(`SettingsFeature.Path.backup`, 실행 경로 settings/backup) — 한 화면에 「백업 만들기」 · 「백업 불러오기」 두 흐름
//  (설계 docs/backup-import-design.md §1 · §3 · §4).
//

import Foundation

import ComposableArchitecture

/// 「필사 백업」 화면.
///
/// - 「백업 만들기」(`BackupExportFeature`)는 화면의 줄과 그 흐름 시트를 맡는다 — 구매 확인 · 암호 · 마지막 필기 저장(flush) · 파일 만들기 · 저장할 곳.
///   flush 요청(`export(.delegate(.canvasFlushRequested))`)은 코디네이터가 받아 필사 화면으로 중계하고, 답은 `SettingsFeature.canvasFlushFinished`
///   를 거쳐 `export(.canvasFlushFinished)` 로 돌아온다(설계 §5-2).
/// - 「백업 불러오기」(`BackupImportFeature`)는 시트다. 구매와 상관없이 열린다(정책 §6-4).
@Reducer
public struct BackupFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        public static let initialState = Self()
        /// 「백업 만들기」 — 화면의 줄과 그 흐름 시트.
        public var export = BackupExportFeature.State()
        /// 「백업 불러오기」 시트. nil 이면 닫혀 있다.
        @Presents public var importer: BackupImportFeature.State?

        public init() { }
    }

    public enum Action: ViewAction {
        /// 「백업 만들기」 의 사건 — flush 요청 · 광고 제거 요청은 부모(설정 · 코디네이터)가 이 경로로 받는다.
        case export(BackupExportFeature.Action)
        /// 「백업 불러오기」 시트의 사건.
        case importer(PresentationAction<BackupImportFeature.Action>)
        case view(View)

        public enum View: Sendable {
            /// 「백업 불러오기」 줄의 불러오기 — 시트를 연다.
            case importTapped
        }
    }

    public var body: some Reducer<State, Action> {
        Scope(state: \.export, action: \.export) {
            BackupExportFeature()
        }
        Reduce { state, action in
            switch action {
            case .view(.importTapped):
                // 「백업 만들기」 흐름이 떠 있으면 그 시트가 화면을 덮고 있다 — 겹쳐 열지 않는다.
                guard !state.export.isFlowPresented else { return .none }
                state.importer = BackupImportFeature.State()
                return .none
            case .export, .importer:
                return .none
            }
        }
        .ifLet(\.$importer, action: \.importer) {
            BackupImportFeature()
        }
    }
}
