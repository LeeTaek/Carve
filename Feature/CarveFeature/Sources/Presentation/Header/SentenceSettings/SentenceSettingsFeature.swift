//
//  SentenceSettingsFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

@Reducer
public struct SentenceSettingsFeature {
    @ObservableState
    public struct State {
        public var sampleSentence: VerseTextFeature.State = .init(chapterTitle: nil,
                                                                 verse: 16,
                                                                 sentence: "하나님이 세상을 이처럼 사랑하사 독생자를 주셨으니 이는 저를 믿는 자마다 멸망치 않고 영생을 얻게 하려 하심이니라")
        @Shared(.appStorage("sentenceSetting")) public var setting: SentenceSetting = .initialState
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static var initialState: Self = .init()
    }
    public enum Action: BindableAction {
        case sampleSentence(VerseTextFeature.Action)
        case binding(BindingAction<State>)
    }
    public var body: some Reducer<State, Action> {
        BindingReducer()
    }
    
}
