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
        @Shared(.appStorage(SentenceSetting.appStorageKey)) public var setting: SentenceSetting = .initialState
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

    @Dependency(\.sentenceSettingBackup) var sentenceSettingBackup

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setFontFamily(let fontFamily):
                return updateSetting(&state) { $0.fontFamily = fontFamily }

            case .setFontSize(let fontSize):
                return updateSetting(&state) { $0.fontSize = fontSize }

            case .setLineSpace(let lineSpace):
                return updateSetting(&state) { $0.lineSpace = lineSpace }

            case .setTraking(let traking):
                return updateSetting(&state) { $0.traking = traking }

            case .setLeftHanded(let isLeftHanded):
                state.$isLeftHanded.withLock { $0 = isLeftHanded }
                return .none

            case .setAllowFingerDrawing(let allowFingerDrawing):
                state.$allowFingerDrawing.withLock { $0 = allowFingerDrawing }
                return .none

            case .resetSetting:
                return updateSetting(&state) { $0 = .initialState }
            }
        }
    }

    /// 본문 모양을 바꾸고, 네 항목(글꼴 · 글자 크기 · 줄 간격 · 자간)이 실제로 달라졌을 때만 iCloud 에 백업한다.
    ///
    /// 슬라이더를 건드리기만 한 것은 이 설치의 선택으로 치지 않는다 — 재설치 뒤 아직 내려오지 않은 백업을 막지 않게 한다.
    /// 왼손 모드 · 손가락 필사는 기기마다 다르게 쓸 수 있어 백업하지 않는다.
    private func updateSetting(_ state: inout State, _ update: (inout SentenceSetting) -> Void) -> Effect<Action> {
        let previous = SentenceSettingBackup(state.setting)
        state.$setting.withLock(update)
        let setting = state.setting
        guard SentenceSettingBackup(setting) != previous else { return .none }
        return .run { _ in
            sentenceSettingBackup.saveUserChoice(setting)
        }
    }
}
