//
//  PopupFeature.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

/// 설정의 확인 · 알림 대화상자 (시안 F2).
///
/// 문구는 네 자리로 나뉜다 — 제목 · 본문 · **되돌릴 수 없다는 경고**(빨강) · 보조 안내.
/// 시안이 그 셋을 색과 크기로 구분하기 때문에 한 덩어리 문자열로는 그릴 수 없다.
@Reducer
public struct PopupFeature {
    @ObservableState
    public struct State: Hashable {
        public static var initialState = Self()
        public var title: String?
        public var body: String = ""
        /// 되돌릴 수 없다는 줄. 빨간 글씨로 따로 세운다.
        public var emphasis: String?
        /// 대안을 알려 주는 보조 줄 (시안 F2 — 「한 절만 비우려면…」).
        public var hint: String?
        public var confirmTitle: String = ""
        public var cancelTitle: String?
        public var role: Role = .plain
        public var confirmAction: ConfirmAction = .dismiss
    }

    /// 대화상자의 성격. 경고 표시와 확인 버튼 색이 여기서 갈린다.
    public enum Role: Equatable, Hashable, Sendable {
        /// 알림 — 표시 없이 확인 버튼 하나.
        case plain
        /// 되돌릴 수 없는 동작 — 경고 표시와 빨간 확인 버튼.
        case destructive
    }

    public enum ConfirmAction: Equatable {
        case dismiss
        case deleteAllData
    }

    public enum Action: ViewAction {
        case setTitle(String)
        case setBody(String)
        case setConfirmTitle(String)
        case setCancelTitle(String)
        case view(View)

        public enum View {
            case confirm
            case cancel
        }
    }

    public init() { }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setTitle(let title):
                state.title = title
            case .setBody(let body):
                state.body = body
            case .setConfirmTitle(let confirmTitle):
                state.confirmTitle = confirmTitle
            case .setCancelTitle(let cancelTitle):
                state.cancelTitle = cancelTitle
            default: break
            }
            return .none
        }
    }
}
