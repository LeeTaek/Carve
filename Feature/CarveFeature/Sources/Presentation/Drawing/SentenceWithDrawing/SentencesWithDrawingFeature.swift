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
        /// 행 ID(`rowID(page:verse:)`) — 장 레이아웃 실측(`VerseGeometryCollector`)이 행을 가리키는 키다. 저장하지 않는다.
        public let id: String
        /// 이 행의 절 본문
        public let sentence: BibleVerse
        /// 본문 텍스트와 밑줄 상태
        public var sentenceState: VerseTextFeature.State
        /// 왼손잡이 배치 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false

        /// - Parameters:
        ///   - sentence: 절 본문(장 · 번역본 포함).
        ///   - notebook: 이 행을 여는 필사책 — 행 ID 에 든다. 기본값이 없다(필사책 결정 12): 빠뜨리면 필사책을 바꿔도 행이 그대로 남아
        ///     다시 재지 않는다.
        public init(sentence: BibleVerse, notebook: NotebookID) {
            self.id = Self.rowID(page: NotebookChapter(notebook: notebook, chapter: sentence.title), verse: sentence.verse)
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       verseEnd: sentence.verseEnd,
                                       sentence: sentence.sentenceScript)
        }

        /// 빈 화면의 자리표시 행 — 본문을 읽기 전이라 기본 필사책으로 둔다(저장 경로가 아니다).
        public static let initialState = Self(sentence: BibleVerse.initialState, notebook: .default)

        /// 절 행의 ID. 메모리에서만 쓴다 — 행 비교(`==`) · 뷰 `ForEach` · 실측 묶음(`verseGeometryMeasured`)의 키다. 저장하지 않는다.
        ///
        /// page(필사책 · 번역본 · 권 · 장)마다 다르다 — 같은 권 · 장을 번역본이나 필사책만 바꿔 열면 행이 새로 생겨 다시 재고(이전 page 의
        /// 실측이 새 본문에 붙지 않는다 · 같은 행이면 실측이 다시 오지 않아 레이아웃이 완성되지 않는다), 뷰의 장 전환 스크롤
        /// (`onChange(of: sentenceWithDrawingState)`)이 돈다. 같은 id 면 `==` 가 같다고 보아 본문이 바뀌지 않는다.
        /// 권 이름은 필사 행과 같은 키(`StoredBookKey.titleName(for:)`)로 짓는다 — 앱 언어와 무관한 `rawValue` 형식이고(영어 현지화 결정 3),
        /// 번역본 · 필사책 접두가 그대로 든다. 이전 필사 시트의 id(`VerseDrawingHistoryFeature.State.id`)와 같은 키다.
        /// - Parameters:
        ///   - page: 행의 필사책과 장(번역본 포함).
        ///   - verse: 절 번호.
        /// - Returns: `1-01Genesis.txt/1/1` · `KJV-1-01Genesis.txt/1/1` · `nb_<토큰>~1-01Genesis.txt/1/1` 처럼 권 키 · 장 · 절을 이은 문자열.
        ///   부작용 없음.
        static func rowID(page: NotebookChapter, verse: Int) -> String {
            "\(StoredBookKey.titleName(for: page))/\(page.chapter.chapter)/\(verse)"
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
