//
//  WidgetSettingsFeature.swift
//  SettingsFeature
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 설정 → 위젯(시안 N7) — 지금 위젯이 돌리는 말씀들, 고르기(시안 N8), 모두 빼기, 홈 화면 추가 안내.
///
/// 즐겨찾기가 보관함이고 그중 **여러 말씀**을 골라 위젯에 담는다(2026-09-16 디자인 결정).
/// 담은 말씀은 1시간마다 한 바퀴씩 돌며 보인다(`WidgetVerseRotation`).
/// 고르는 것과 홈 화면에 위젯을 두는 것은 별개라, 화면 아래에 추가 방법을 함께 안내한다.
@Reducer
public struct WidgetSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()

        /// 즐겨찾기 전체 — 고르는 시트(시안 N8)가 쓴다. 최근 추가순이다.
        var favorites: IdentifiedArrayOf<FavoriteVerseSnapshot> = []
        /// 지금 위젯에 담긴 말씀들. 담은 순서다.
        var selectedKeys: [FavoriteVerseKey] = []
        /// 첫 조회가 끝났는가. 조회 중에 「고르지 않음」 이 깜빡이지 않게 한다.
        var hasLoaded = false
        /// 고르는 시트가 떠 있는가(시안 N8).
        var isPickerPresented = false
        /// 시트에서 고른 말씀들. 「적용」 을 눌러야 위젯이 바뀐다 — 취소하면 기존 목록을 유지한다.
        var pickerSelection: Set<FavoriteVerseKey> = []
        /// 바꾸는 중 — 버튼을 잠근다.
        var isChanging = false

        /// 담긴 말씀의 보관본. 즐겨찾기에서 사라진 말씀은 뺀다.
        var selected: [FavoriteVerseSnapshot] {
            selectedKeys.compactMap { favorites[id: $0] }
        }

        /// 더 담을 수 있는가.
        var canSelectMore: Bool {
            pickerSelection.count < WidgetVerseLimit.maximum
        }

        public init() { }
    }

    public enum Action: ViewAction {
        /// 즐겨찾기와 지금 담긴 말씀들을 읽었다.
        case loaded(favorites: [FavoriteVerseSnapshot], selection: [FavoriteVerseKey])
        /// 변경이 끝났다. 성공하면 바뀐 목록이 온다.
        case changeFinished([FavoriteVerseKey], failed: Bool)
        case view(View)

        @CasePathable
        public enum View {
            case task
            /// 「말씀 고르기」 · 「고른 말씀 바꾸기」.
            case changeTapped
            /// 「위젯에서 모두 빼기」.
            case clearTapped
            /// 고르는 시트를 여닫는다.
            case setPickerPresented(Bool)
            /// 시트에서 말씀을 켜거나 껐다.
            case pickerToggled(FavoriteVerseKey)
            /// 시트의 「적용」.
            case pickerApplyTapped
        }
    }

    @Dependency(\.favoriteVerseRepository) var repository
    @Dependency(\.widgetVerseClient) var widgetVerseClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.task):
                return .run { [repository, widgetVerseClient] send in
                    let selection = await widgetVerseClient.selection()
                    let favorites = (try? await repository.favorites()) ?? []
                    await send(.loaded(favorites: favorites, selection: selection))
                }

            case let .loaded(favorites, selection):
                state.favorites = IdentifiedArray(favorites, uniquingIDsWith: { newer, _ in newer })
                // 즐겨찾기에서 사라진 말씀은 화면에서도 뺀다 — 위젯 쪽은 해제할 때 함께 정리된다.
                state.selectedKeys = selection.filter { state.favorites[id: $0] != nil }
                state.hasLoaded = true
                return .none

            case .view(.changeTapped):
                state.pickerSelection = Set(state.selectedKeys)
                state.isPickerPresented = true
                return .none

            case .view(.setPickerPresented(let isPresented)):
                state.isPickerPresented = isPresented
                return .none

            case .view(.pickerToggled(let key)):
                if state.pickerSelection.contains(key) {
                    state.pickerSelection.remove(key)
                } else if state.canSelectMore {
                    state.pickerSelection.insert(key)
                }
                return .none

            case .view(.pickerApplyTapped):
                state.isPickerPresented = false
                // 목록 순서(최근 추가순)를 그대로 담는 순서로 삼는다.
                let favorites = state.favorites.filter { state.pickerSelection.contains($0.key) }
                let keys = favorites.map(\.key)
                guard keys != state.selectedKeys else { return .none }
                state.isChanging = true
                return .run { [widgetVerseClient] send in
                    do {
                        try await widgetVerseClient.select(Array(favorites))
                        await send(.changeFinished(keys, failed: false))
                    } catch {
                        Log.error("위젯에 담지 못했다", error)
                        await send(.changeFinished([], failed: true))
                    }
                }

            case .view(.clearTapped):
                guard !state.selectedKeys.isEmpty else { return .none }
                state.isChanging = true
                return .run { [widgetVerseClient] send in
                    do {
                        try await widgetVerseClient.clear()
                        await send(.changeFinished([], failed: false))
                    } catch {
                        Log.error("위젯을 비우지 못했다", error)
                        await send(.changeFinished([], failed: true))
                    }
                }

            case let .changeFinished(keys, failed):
                state.isChanging = false
                // 실패하면 저장된 값이 그대로다 — 화면도 그대로 둔다.
                guard !failed else { return .none }
                state.selectedKeys = keys
                return .none
            }
        }
    }
}
