//
//  SentenceReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import Resources
import SwiftUI

import ComposableArchitecture

@Reducer
public struct SentenceReducer {
    public init() { }
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var chapterTitle: String?
        public let section: Int
        public let sentence: String
        public var sentenceSetting: SentenceSetting = .initialState
        
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
                                                   sentence: "태초에 하나님이 천지를 창조하시니라")

    }
    
    public enum Action: FeatureAction {
        case view(ViewAction)
        case inner(InnerAction)
    }
    
    public enum ViewAction {
        case setSentenceSetting(SentenceSetting)
    }
    
    public enum InnerAction {
        case present
        case redrawUnderline(CGRect)
    }
    
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.setSentenceSetting(let setting)):
                state.sentenceSetting = setting
            default: break
            }
            return .none
        }
    }
}
