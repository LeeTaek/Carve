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
        /// 행 ID(`rowID(chapter:verse:)`) — 장 레이아웃 실측(`VerseGeometryCollector`)이 행을 가리키는 키다. 저장하지 않는다.
        public let id: String
        /// 이 행의 절 본문
        public let sentence: BibleVerse
        /// 본문 텍스트와 밑줄 상태
        public var sentenceState: VerseTextFeature.State
        /// 왼손잡이 배치 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false

        public init(sentence: BibleVerse) {
            self.id = Self.rowID(chapter: sentence.title, verse: sentence.verse)
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       verseEnd: sentence.verseEnd,
                                       sentence: sentence.sentenceScript)
        }

        public static let initialState = Self(sentence: BibleVerse.initialState)

        /// 절 행의 ID. 메모리에서만 쓴다 — 행 비교(`==`) · 뷰 `ForEach` · 실측 묶음(`verseGeometryMeasured`)의 키다. 저장하지 않는다.
        ///
        /// 번역본마다 다르다 — 같은 권 · 장을 번역본만 바꿔 열면 행이 새로 생겨 다시 재고(이전 번역본 실측이 새 본문에 붙지 않는다),
        /// 뷰의 장 전환 스크롤(`onChange(of: sentenceWithDrawingState)`)이 돈다. 같은 id 면 `==` 가 같다고 보아 본문이 바뀌지 않는다.
        /// 앱 언어와 무관하게 같은 값이 되도록 화면 이름이 아니라 `rawValue`(번역본 · 권)로 짓는다(영어 현지화 결정 3).
        /// 저장되는 `titleName`(`StoredBookKey`)과는 다른 메모리 전용 형식이다.
        /// - Parameters:
        ///   - chapter: 행의 장(번역본 포함).
        ///   - verse: 절 번호.
        /// - Returns: `NKRV/1-01Genesis.txt/1/1` · `KJV/1-01Genesis.txt/1/1` 처럼 번역본 · 권 · 장 · 절을 이은 문자열. 부작용 없음.
        static func rowID(chapter: BibleChapter, verse: Int) -> String {
            "\(chapter.translation.rawValue)/\(chapter.title.rawValue)/\(chapter.chapter)/\(verse)"
        }
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
