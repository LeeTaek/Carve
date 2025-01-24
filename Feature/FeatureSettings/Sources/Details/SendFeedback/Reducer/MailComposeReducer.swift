//
//  MailComposeReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

@Reducer
public struct MailComposeReducer {
    @ObservableState
    public struct State: Equatable, Hashable {
        public static var initialState = Self(mailInfo: .initialState)
        public var isPresent: Bool = false
        public var mailInfo: UserFeedback
        public init(mailInfo: UserFeedback) {
            self.mailInfo = mailInfo
        }
    }
    public enum Action {
        case dismiss
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .dismiss:
                state.isPresent = false
            }
            return .none
        }
    }
}
