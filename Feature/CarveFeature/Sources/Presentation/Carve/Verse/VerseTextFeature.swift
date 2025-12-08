//
//  VerseTextFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Resources
import SwiftUI

import ComposableArchitecture


/// 한 절(verse)의 텍스트 및 밑줄(underline) 상태 관리
@Reducer
public struct VerseTextFeature {
    public init() { }
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        /// 성경 제목 및 장
        public var chapterTitle: String?
        /// 성경 절
        public let verse: Int
        /// 성경 문장
        public let sentence: String
        /// 각 텍스트 라인의 하단 Offset
        public var underlineOffsets: [CGFloat] = []
        /// 화면 복귀시 underline preferenceKey 재설정을 위한 key
        public var preferenceVersion: UUID = .init()
        
        /// 문장 폰트 등 설정
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        
        public init(
            chapterTitle: String?,
            verse: Int,
            sentence: String
        ) {
            self.id = String(verse) + sentence
            self.chapterTitle = chapterTitle
            self.verse = verse
            self.sentence = sentence
        }
        
        public static let initialState = Self.init(
            chapterTitle: nil,
            verse: 1,
            sentence: "태초에 하나님이 천지를 창조하시니라"
        )
        
    }
    
    public enum Action {
        /// 각 라인의 밑줄 Offset을 상태에 반영하는 액션.
        /// 밑줄 offset 계산 및 갱신은 Feature(CarveDetailFeature)의 .view(.underlineLayoutChanged)`에서 수행,
        /// 이 액션은 주로 Preview 환경에서 레이아웃 변경 결과를 직접 상태에 주입할 때 사용.
        case setUnderlineOffsets([CGFloat])
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setUnderlineOffsets(let offsets):
                state.underlineOffsets = offsets
                return .none
            }
        }
    }
    
    
    /// 밑줄 offset 계산,
    /// - Parameters:
    ///   - textLayout: 변경된 TextPreference
    ///   - sentenceSetting: 폰트, 자간 등 설정
    public static func makeUnderlineOffsets(
        from textLayout: Text.LayoutKey.Value,
        sentenceSetting: SentenceSetting
    ) -> [CGFloat] {
        let layoutLines = textLayout.map { $0.layout.compactMap { $0 } }.flatMap(\.self)
        
        let fontSize = sentenceSetting.fontSize
        let uiFont = sentenceSetting.fontFamily.font(size: fontSize)
        let descender = uiFont.descender.magnitude
        
        return layoutLines.map { $0.origin.y + descender }
    }
}
