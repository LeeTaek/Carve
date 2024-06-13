//
//  SentenceSettingsReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

@Reducer
public struct SentenceSettingsReducer {
    @ObservableState
    public struct State {
        public var sampleSentence: SentenceReducer.State = .init(chapterTitle: nil,
                                                                 section: 16,
                                                                 sentence: "하나님이 세상을 이처럼 사랑하사 독생자를 주셨으니 이는 저를 믿는 자마다 멸망치 않고 영생을 얻게 하려 하심이니라")
        public var setting: SentenceSetting
        public static var initialState: Self = .init(setting: .initialState)
    }
    public enum Action {
        case setLineSpace(CGFloat)
        case setFontSize(CGFloat)
        case setTraking(CGFloat)
        case setFontFamily(FontCase)
        case sampleSentence(SentenceReducer.Action)
    }
    public var body: some Reducer<State, Action> {
        Scope(state: \.sampleSentence, action: \.sampleSentence) {
            SentenceReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .setLineSpace(let space):
                state.setting.lineSpace = space
            case .setTraking(let tracking):
                state.setting.traking = tracking
            case .setFontSize(let size):
                state.setting.fontSize = size
            case .setFontFamily(let font):
                state.setting.fontFamily = font
            case .sampleSentence(.view(.setSentenceSetting)):
                return .none
            default: break
            }
            return .run { [setting = state.setting] send in
                await send(.sampleSentence(.view(.setSentenceSetting(setting))))
            }
        }
    }
    
}
