//
//  SentenceFeature.swift
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

@Reducer
public struct SentenceFeature {
    public init() { }
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var chapterTitle: String?
        public let verse: Int
        public let sentence: String
        public var underlineOffsets: [CGFloat] = []
        
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
       
        public init(chapterTitle: String?,
                    verse: Int,
                    sentence: String) {
            self.id = String(verse) + sentence
            self.chapterTitle = chapterTitle
            self.verse = verse
            self.sentence = sentence
        }
        
        public static let initialState = Self.init(chapterTitle: nil,
                                                   verse: 1,
                                                   sentence: "태초에 하나님이 천지를 창조하시니라")

    }
    
    public enum Action {
        case setUnderlineOffsets(Text.LayoutKey.Value)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setUnderlineOffsets(let textLayout):
                let layoutLines = textLayout.map { $0.layout.compactMap { $0 } }.flatMap(\.self)
                
                let fontSize = state.sentenceSetting.fontSize
                let uiFont = state.sentenceSetting.fontFamily.font(size: fontSize)
                let decender = uiFont.descender.magnitude
                
                let lineOffests = layoutLines.map { $0.origin.y + decender }
                
                state.underlineOffsets = lineOffests
                return .none
            }
        }
    }
}
