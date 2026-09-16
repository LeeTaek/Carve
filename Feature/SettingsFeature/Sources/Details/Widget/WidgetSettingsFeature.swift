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

/// 설정 → 위젯(시안 N7) — 지금 표시 중인 말씀, 표시할 말씀 바꾸기(시안 N8), 표시 해제, 홈 화면 추가 안내.
///
/// 즐겨찾기가 보관함이고 그중 **한 말씀**을 골라 위젯에 표시한다(2026-09-16 디자인 결정).
/// 고르는 것과 홈 화면에 위젯을 두는 것은 별개라, 화면 아래에 추가 방법을 함께 안내한다.
@Reducer
public struct WidgetSettingsFeature {
    public init() { }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()

        /// 즐겨찾기 전체 — 고르는 시트(시안 N8)가 쓴다. 최근 추가순이다.
        var favorites: IdentifiedArrayOf<FavoriteVerseSnapshot> = []
        /// 지금 위젯에 표시 중인 말씀. 고르지 않았으면 nil.
        var current: FavoriteVerseSnapshot?
        /// 첫 조회가 끝났는가. 조회 중에 「고르지 않음」 이 깜빡이지 않게 한다.
        var hasLoaded = false
        /// 고르는 시트가 떠 있는가(시안 N8).
        var isPickerPresented = false
        /// 시트에서 고른 말씀. 「적용」 을 눌러야 위젯이 바뀐다 — 취소하면 기존 대상을 유지한다.
        var pickerSelection: FavoriteVerseKey?
        /// 바꾸는 중 — 버튼을 잠근다.
        var isChanging = false

        public init() { }
    }

    public enum Action: ViewAction {
        /// 즐겨찾기와 지금 표시 중인 말씀을 읽었다.
        case loaded(favorites: [FavoriteVerseSnapshot], selection: FavoriteVerseKey?)
        /// 표시 변경이 끝났다. 성공하면 바뀐 말씀(해제면 nil)이 온다.
        case changeFinished(FavoriteVerseSnapshot?, failed: Bool)
        case view(View)

        @CasePathable
        public enum View {
            case task
            /// 「표시할 말씀 바꾸기」.
            case changeTapped
            /// 「위젯 표시 해제」.
            case clearTapped
            /// 고르는 시트를 여닫는다.
            case setPickerPresented(Bool)
            /// 시트에서 말씀을 골랐다.
            case pickerSelected(FavoriteVerseKey)
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
                    let selection = await widgetVerseClient.selection()?.key
                    let favorites = (try? await repository.favorites()) ?? []
                    await send(.loaded(favorites: favorites, selection: selection))
                }

            case let .loaded(favorites, selection):
                state.favorites = IdentifiedArray(favorites, uniquingIDsWith: { newer, _ in newer })
                state.current = selection.flatMap { state.favorites[id: $0] }
                state.hasLoaded = true
                return .none

            case .view(.changeTapped):
                state.pickerSelection = state.current?.key
                state.isPickerPresented = true
                return .none

            case .view(.setPickerPresented(let isPresented)):
                state.isPickerPresented = isPresented
                return .none

            case .view(.pickerSelected(let key)):
                state.pickerSelection = key
                return .none

            case .view(.pickerApplyTapped):
                guard let key = state.pickerSelection, let favorite = state.favorites[id: key] else {
                    state.isPickerPresented = false
                    return .none
                }
                state.isPickerPresented = false
                state.isChanging = true
                return .run { [widgetVerseClient] send in
                    do {
                        try await widgetVerseClient.select(favorite)
                        await send(.changeFinished(favorite, failed: false))
                    } catch {
                        Log.error("위젯에 표시하지 못했다", error)
                        await send(.changeFinished(nil, failed: true))
                    }
                }

            case .view(.clearTapped):
                guard state.current != nil else { return .none }
                state.isChanging = true
                return .run { [widgetVerseClient] send in
                    do {
                        try await widgetVerseClient.clear()
                        await send(.changeFinished(nil, failed: false))
                    } catch {
                        Log.error("위젯 표시를 해제하지 못했다", error)
                        await send(.changeFinished(nil, failed: true))
                    }
                }

            case let .changeFinished(favorite, failed):
                state.isChanging = false
                // 실패하면 저장된 값이 그대로다 — 화면도 그대로 둔다.
                guard !failed else { return .none }
                state.current = favorite
                return .none
            }
        }
    }
}
