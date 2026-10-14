//
//  AppVersionFeature.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

@Reducer
public struct AppVersionFeature {
    public init() { }
    
    @ObservableState
    public struct State: Equatable, Hashable, Sendable {
        public static let initialState = Self()
        public var path = StackState<Path.State>()
        public var iCloudIsOn: Bool = true
    }
    public enum Action {
        case path(StackActionOf<Path>)
        /// 「앱 정보」 의 「성경 본문 출처」 행을 눌렀을 때(영어 현지화 결정 11).
        case pushToBibleSource
        case pushToLisence
        case setiCloud(Bool)
    }
    
    @Reducer
    public enum Path {
        case lisence(LisenceFeature)
        /// 성경 본문 출처 — 번역본마다 이름 · 판 · 권리 · 출처(결정 11).
        case bibleSource(BibleSourceFeature)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .pushToBibleSource:
                state.path.append(.bibleSource(.initialState))
            case.pushToLisence:
                state.path.append(.lisence(.initialState))
            case .setiCloud(let isOn):
                state.iCloudIsOn = isOn
            default: break
            }
            return .none
        }
        .forEach(\.path, action: \.path)
    }
}

extension AppVersionFeature.Path.State: Hashable {}
extension AppVersionFeature.Path.State: Sendable {}
