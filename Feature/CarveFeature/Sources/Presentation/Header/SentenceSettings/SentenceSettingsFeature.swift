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
    /// `@Shared` 값은 `BindingReducer`로 쓸 수 없다.
    /// `Shared.wrappedValue`의 setter가 `unavailable`이라 `$store.setting` 같은 직접 바인딩은
    /// 컴파일러 버전에 따라 통과하기도, 실패하기도 한다. 액션으로 받아 `withLock`으로 쓴다.
    public enum Action {
        case setFontFamily(FontCase)
        case setFontSize(CGFloat)
        case setLineSpace(CGFloat)
        case setTraking(CGFloat)
        case setLeftHanded(Bool)
        case setAllowFingerDrawing(Bool)
        case resetSetting
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setFontFamily(let fontFamily):
                state.$setting.withLock { $0.fontFamily = fontFamily }

            case .setFontSize(let fontSize):
                state.$setting.withLock { $0.fontSize = fontSize }

            case .setLineSpace(let lineSpace):
                state.$setting.withLock { $0.lineSpace = lineSpace }

            case .setTraking(let traking):
                state.$setting.withLock { $0.traking = traking }

            case .setLeftHanded(let isLeftHanded):
                state.$isLeftHanded.withLock { $0 = isLeftHanded }

            case .setAllowFingerDrawing(let allowFingerDrawing):
                state.$allowFingerDrawing.withLock { $0 = allowFingerDrawing }

            case .resetSetting:
                state.$setting.withLock { $0 = .initialState }
            }
            return .none
        }
    }
    
}
