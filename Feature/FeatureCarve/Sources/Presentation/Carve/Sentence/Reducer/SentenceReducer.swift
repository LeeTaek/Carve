//
//  SentenceReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentenceReducer {
    public init() { }
    @ObservableState
    public struct State: Equatable, Identifiable {
        public var id: String
        public var chapterTitle: String?
        public let section: Int
        public let sentence: String
        public var lineSpace: CGFloat = 30
        public var fontSize: CGFloat = 20
        public var traking: CGFloat = 1
        public var baseLineHeight: CGFloat = 20
        public var textHeight: CGFloat = .zero
        public var font: FontCase = .flower
        public var lineCount: Int = 3
        
        public init(chapterTitle: String?,
                    section: Int,
                    sentence: String,
                    lineSpace: CGFloat,
                    fontSize: CGFloat,
                    traking: CGFloat,
                    baseLineHeight: CGFloat,
                    textHeight: CGFloat,
                    font: FontCase,
                    lineCount: Int) {
            self.id = String(section) + sentence
            self.chapterTitle = chapterTitle
            self.section = section
            self.sentence = sentence
            self.lineSpace = lineSpace
            self.fontSize = fontSize
            self.traking = traking
            self.baseLineHeight = baseLineHeight
            self.textHeight = textHeight
            self.font = font
            self.lineCount = lineCount
        }
        
        public init(chapterTitle: String?,
                    section: Int,
                    sentence: String) {
            self.id = String(section) + sentence
            self.chapterTitle = chapterTitle
            self.section = section
            self.sentence = sentence
        }
        
        public static let initialState = Self.init(chapterTitle: nil,
                                                   section: 1,
                                                   sentence: "태초에 하나님이 천지를 ")

    }
    
    public enum Action: FeatureAction {
        case view(ViewAction)
        case inner(InnerAction)
//        case redrawUnderline(CGRect)
    }
    
    public enum ViewAction {
        case setLineSpace(CGFloat)
        case setFontSize(CGFloat)
        case setTraking(CGFloat)
        case setFont(FontCase)
    }
    
    public enum InnerAction {
        case present
        case redrawUnderline(CGRect)
    }
    
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .inner(.present):
                state.lineCount = getLine(textHeight: state.textHeight,
                                           lineSpace: state.lineSpace,
                                           baseLineHeight: state.baseLineHeight)
                return .none
            case .view(.setLineSpace(let lineSpace)):
                state.lineSpace = lineSpace
            case .view(.setFontSize(let fontSize)):
                state.fontSize = fontSize
            case .view(.setTraking(let tracking)):
                state.traking = tracking
            case .view(.setFont(let font)):
                state.font = font
            case .inner(.redrawUnderline(let rect)):
                return .none
            }
            return .run { send in
                await send(.inner(.present))
            }
        }
    }
    
    private func getLine(textHeight: CGFloat, lineSpace: CGFloat, baseLineHeight: CGFloat) -> Int {
        let count = Int((textHeight + lineSpace + 25) / (baseLineHeight + lineSpace)) + 1
        Log.debug("라인 수", count)
        return count
    }
    
}

public enum FontCase: String, CaseIterable {
    case gothic = "NanumBarunGothic"
    case myeongjo = "NanumMyeongjo"
    case flower = "NanumFlowerScent"
    
        
    public func font(size: CGFloat) -> UIFont {
        UIFont(name: self.rawValue, size: size) ?? UIFont.systemFont(ofSize: size)
    }
}
