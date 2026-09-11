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
        @Shared(.appStorage("sentenceSetting")) public var setting: SentenceSetting = .initialState
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static var initialState: Self = .init()
    }
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
    }
    public var body: some Reducer<State, Action> {
        BindingReducer()
    }
    
}
