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
                                                                 verse: 16,
                                                                 sentence: "하나님이 세상을 이처럼 사랑하사 독생자를 주셨으니 이는 저를 믿는 자마다 멸망치 않고 영생을 얻게 하려 하심이니라")
        @Shared(.appStorage("sentenceSetting")) public var setting: SentenceSetting = .initialState
        public static var initialState: Self = .init()
    }
    public enum Action {
        case setLineSpace(CGFloat)
        case setFontSize(CGFloat)
        case setTraking(CGFloat)
        case setFontFamily(FontCase)
        case sampleSentence(SentenceReducer.Action)
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setLineSpace(let space):
                state.$setting.withLock { $0.lineSpace = space }
            case .setTraking(let tracking):
                state.$setting.withLock { $0.traking = tracking }
            case .setFontSize(let size):
                state.$setting.withLock { $0.fontSize = size }
            case .setFontFamily(let font):
                state.$setting.withLock { $0.fontFamily = font }
            default: break
            }
            return .none
        }
    }
    
}
