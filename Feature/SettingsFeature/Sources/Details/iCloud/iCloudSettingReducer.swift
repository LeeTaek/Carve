//
//  CloudSettingsFeature.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct CloudSettingsFeature {
    public init() { }
    
    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        @Presents public var path: Path.State?
        public var iCloudIsOn: Bool = true
        public var isLoading: Bool = false
    }
    @Dependency(\.createSwiftDataActor) private var database
    @Dependency(\.widgetVerseClient) private var widgetVerseClient

    public enum Action: ViewAction {
        case path(PresentationAction<Path.Action>)
        case setiCloud(Bool)
        case removeAlliCloudData
        /// 삭제가 끝났다 — 열려 있는 장에 알린다.
        case drawingDataCleared
        case presentPopover(
            title: String? = nil,
            body: String,
            emphasis: String? = nil,
            hint: String? = nil,
            confirmTitle: String,
            cancelTitle: String? = nil,
            role: PopupFeature.Role = .plain,
            action: PopupFeature.ConfirmAction
        )
        case popupDismiss
        case setLoading(Bool)
        case view(View)
        
        public enum View {
            case databaseIsEmpty
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setiCloud(let ison):
                state.iCloudIsOn = ison
            case .view(.databaseIsEmpty):
                return .run { [widgetVerseClient] send in
                    // 「필사 데이터」 에는 즐겨찾기에 복사해 둔 필기와 위젯에 담은 말씀도 포함된다 — 셋을 함께 본다.
                    let hasDrawings = !(try await database.databaseIsEmpty(BibleDrawing.self))
                    let hasFavorites = !(try await database.databaseIsEmpty(FavoriteVerse.self))
                    let hasWidgetVerses = !(await widgetVerseClient.selection().isEmpty)
                    if hasDrawings || hasFavorites || hasWidgetVerses {
                        // 문구와 구성은 시안 F2 를 따른다 — 지워지는 범위 · 되돌릴 수 없다는 경고 · 한 절만 비우는 대안.
                        await send(.presentPopover(
                            title: "모든 필사 데이터를 지울까요?",
                            body: """
                            모든 장의 필기와 이전 필사 기록이 지워져요.
                            즐겨찾기와 위젯에 담은 말씀도 함께 사라져요.
                            """,
                            emphasis: "지운 데이터는 되돌릴 수 없어요.",
                            hint: "한 절만 비우려면 해당 절을 길게 눌러\n지우기를 선택해 주세요.",
                            confirmTitle: "모두 지우기",
                            cancelTitle: "취소",
                            role: .destructive,
                            action: .deleteAllData
                        ))
                    } else {
                        await send(.presentPopover(
                            body: "지울 필사 데이터가 없어요.",
                            confirmTitle: "확인",
                            action: .dismiss
                        ))
                    }
                }
            case let .presentPopover(title, body, emphasis, hint, confirmTitle, cancelTitle, role, action):
                state.path = .popup(.init(
                    title: title,
                    body: body,
                    emphasis: emphasis,
                    hint: hint,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    role: role,
                    confirmAction: action
                ))
            case .removeAlliCloudData:
                return .run { [widgetVerseClient] send in
                    await send(.setLoading(true))
                    // 필사 행 · 구 구조 잔존 행 · 즐겨찾기(필기 복사본) · 위젯(App Group 의 필기 PNG)까지 지운다.
                    try await database.deleteAll(BibleDrawing.self)
                    try await database.deleteAll(BiblePageDrawing.self)
                    try await database.deleteAll(FavoriteVerse.self)
                    // 위젯은 별도 저장소라 실패해도 DB 삭제를 되돌릴 수 없다. 남으면 홈 화면에만 옛 말씀이 남는다.
                    do {
                        try await widgetVerseClient.clear()
                    } catch {
                        Log.error("전체 삭제 — 위젯 내용을 비우지 못했다", "\(error)")
                    }
                    await send(.drawingDataCleared)
                    await send(.setLoading(false))

                    await send(.presentPopover(
                        body: "모든 필사 데이터를 지웠어요.",
                        confirmTitle: "확인",
                        action: .dismiss
                    ))
                }

            case .drawingDataCleared:
                // 열려 있는 장이 이 값을 보고 다시 조회한다 (`CarveDetailFeature`).
                // 상태에 두지 않는 이유는 `State` 가 `Hashable` 이기 때문이다 — `@Shared` 는 그 합성을 깬다.
                DrawingDataRevision.bump()
            case .path(.presented(.popup(.view(.confirm)))):
                let shouldDeleteAllData = state.path?.popup?.confirmAction == .deleteAllData
                return .run { send in
                    guard let databaseIsEmpty = try? await database.databaseIsEmpty(BibleDrawing.self) else {
                        return
                    }
                    
                    if shouldDeleteAllData && !databaseIsEmpty {
                        await send(.removeAlliCloudData)
                    } else {
                        await send(.popupDismiss)
                    }
                }
            case .path(.presented(.popup(.view(.cancel)))):
                state.path = nil
            case .popupDismiss:
                state.path = nil
            case .setLoading(let isLoading):
                state.isLoading = isLoading
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}

extension CloudSettingsFeature {
    @Reducer
    public enum Path {
        case popup(PopupFeature)
    }
}

extension CloudSettingsFeature.Path.State: Hashable {}
