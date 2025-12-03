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

@Reducer
public struct VerseRowFeature {
    @ObservableState
    public struct State: Identifiable, Equatable {
        public static func == (lhs: VerseRowFeature.State, rhs: VerseRowFeature.State) -> Bool {
            lhs.id == rhs.id
        }
        public let id: String
        /// 성경 제목, 장, 절을 포함한 도메인 모델
        public let sentence: BibleVerse
        /// 절의 텍스트와 밑줄 정보를 관리하는 VerseTextFeature 상태
        public var sentenceState: VerseTextFeature.State
        /// 해당 절의 필사 history를 관리하는 VerseDrawingHistoryFeature 상태
        public var drewHistoryState: VerseDrawingHistoryFeature.State
        /// 필사 히스토리 시트 노출 여부
        public var isPresentDrewHistory: Bool = false
        /// verse 그릴 UnderLineView의 global 좌표 Rect
        public var verseFrame: CGRect = .zero
        /// 왼손잡이 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false

        public init(sentence: BibleVerse) {
            self.id = "\(sentence.title.title.koreanTitle()).\(sentence.title.chapter).\(sentence.verse)"
            self.sentence = sentence
            self.sentenceState = .init(chapterTitle: sentence.chapterTitle,
                                       verse: sentence.verse,
                                       sentence: sentence.sentenceScript)
            self.drewHistoryState = .init(title: sentence.title, verse: sentence.verse)
        }
        
        public static var initialState = Self(sentence: BibleVerse.initialState)
    }
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        case view(View)
        case scope(ScopeAction)
        
        @CasePathable
        public enum View {
            /// 필사 히스토리 시트의 노출/숨김 설정
            case presentDrewHistory(Bool)
            /// underlineView의 globalRect를 업데이트하며 CarveDetailFeature에 전달
            case updateVerseFrame(CGRect)
        }
    }
    
    @CasePathable
    public enum ScopeAction {
        case sentenceAction(VerseTextFeature.Action)
        case drewHistoryAction(VerseDrawingHistoryFeature.Action)
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.sentenceState,
              action: \.scope.sentenceAction) {
            VerseTextFeature()
        }
        Scope(state: \.drewHistoryState,
              action: \.scope.drewHistoryAction) {
            VerseDrawingHistoryFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.presentDrewHistory(let isPresent)):
                state.isPresentDrewHistory = isPresent
                
            case .view(.updateVerseFrame(let rect)):
                state.verseFrame = rect
                
            case .scope(.drewHistoryAction(.setPresentDrawing)):
                state.isPresentDrewHistory = false

            default: break
                
            }
            return .none
        }
    }
    
}
