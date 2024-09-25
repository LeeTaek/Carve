//
//  iCloudSettingReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct CloudSettingsReducer {
    public init() { }
    
    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        @Presents public var path: Path.State?
        public var iCloudIsOn: Bool = true
    }
    private var database = SwiftDatabaseActor(modelContainer: PersistentCloudKitContainer.shared.container)

    public enum Action {
        case path(PresentationAction<Path.Action>)
        case setiCloud(Bool)
        case databaseIsEmpty
        case removeAlliCloudData
        case presentPopover(title: String? = nil,
                            body: String,
                            confirmTitle: String,
                            cancelTitle: String? = nil,
                            color: Color = .black)
        case popupDismiss
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setiCloud(let ison):
                state.iCloudIsOn = ison
            case .databaseIsEmpty:
                return .run { send in
                    if !(try await database.databaseIsEmpty(DrawingVO.self)) {
                        await send(.presentPopover(title: nil,
                                                   body: "필사 데이터를 삭제하면 다시 복구할 수 없습니다.\n 정말 삭제하시겠습니까?",
                                                   confirmTitle: "삭제",
                                                   cancelTitle: "취소",
                                                   color: .red))
                    } else {
                        await send(.presentPopover(
                            body: "기기에 필사 데이터가 존재하지 않습니다.",
                            confirmTitle: "확인"
                        ))
                    }
                }
            case let .presentPopover(title, body, confirmTitle, cancelTitle, color):
                state.path = .popup(.init(
                    title: title,
                    body: body,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    confirmColor: color
                ))
            case .removeAlliCloudData:
                return .run { send in
                    try await database.deleteAll(DrawingVO.self)
                    await send(.presentPopover(
                        body: "모든 필사 데이터를 삭제했습니다.",
                        confirmTitle: "확인")
                    )
                }
            case .path(.presented(.popup(.confirm))):
                return .run { send in
                    if !(try await database.databaseIsEmpty(DrawingVO.self)) {
                        await send(.removeAlliCloudData)
                    } else {
                        await send(.popupDismiss)
                    }
                }
            case .path(.presented(.popup(.cancel))):
                state.path = nil
            case .popupDismiss:
                state.path = nil
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}

extension CloudSettingsReducer {
    @Reducer(state: .hashable)
    public enum Path {
        case popup(PopupReducer)
    }
}
