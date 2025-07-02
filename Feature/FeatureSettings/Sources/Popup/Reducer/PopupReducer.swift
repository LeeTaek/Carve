//
//  PopupReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@Reducer
public struct PopupReducer {
    @ObservableState
    public struct State: Hashable {
        public static var initialState = Self()
        public var title: String?
        public var body: String = ""
        public var confirmTitle: String = ""
        public var cancelTitle: String?
        public var confirmColor: Color = .black
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
