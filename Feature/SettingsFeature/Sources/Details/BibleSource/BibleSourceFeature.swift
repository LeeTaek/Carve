//
//  BibleSourceFeature.swift
//  SettingsFeature
//
//  설정 → 앱 버전 → 「성경 본문 출처」(영어 현지화 결정 11).
//

import Foundation

import ComposableArchitecture

/// 번역본마다 본문의 이름 · 판 · 권리 · 출처를 보이는 화면. 읽기만 하는 화면이라 액션이 없다.
/// 앱 버전 화면(`AppVersionFeature`)의 「앱 정보」 에서 들어간다.
@Reducer
public struct BibleSourceFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Equatable, Hashable, Sendable {
        public static let initialState = Self()
        /// 화면에 적는 번역본 항목 — `Translation.allCases` 순서(개역개정 · KJV · BSB).
        public var entries: [BibleSourceEntry] = BibleSourceEntry.all
    }

    public enum Action { }

    public var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
