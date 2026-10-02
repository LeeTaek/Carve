//
//  SentencesWithDrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI

import ComposableArchitecture

/// 단일 Canvas 본문 열의 절 행 하나 — 본문 · 밑줄과 그 실측만 맡는다. 잉크는 캔버스(`ChapterCanvasFeature`)가 장 단위로 그린다.
@Reducer
public struct SentencesWithDrawingFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Equatable, Sendable {
        public static func == (lhs: SentencesWithDrawingFeature.State, rhs: SentencesWithDrawingFeature.State) -> Bool {
            lhs.id == rhs.id
        }
        /// 행 ID(`권.장.절`) — 장 레이아웃 실측(`VerseGeometryCollector`)이 행을 가리키는 키다.
        public let id: String
        /// 이 행의 절 본문
        public let sentence: BibleVerse
        /// 본문 텍스트와 밑줄 상태
        public var sentenceState: VerseTextFeature.State
        /// 왼손잡이 배치 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false

        public init(sentence: BibleVerse) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.verse)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       verseEnd: sentence.verseEnd,
                                       sentence: sentence.sentenceScript)
        }

        public static let initialState = Self(sentence: BibleVerse.initialState)
    }

    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        case view(View)
        case scope(ScopeAction)

        @CasePathable
        public enum View {
            case setBible
            case setHeight(height: CGFloat)
        }
    }

    @CasePathable
    public enum ScopeAction {
        /// 본문 텍스트 행의 액션
        case sentenceAction(VerseTextFeature.Action)
    }


    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \.scope.sentenceAction) {
            VerseTextFeature()
        }
    }

}
