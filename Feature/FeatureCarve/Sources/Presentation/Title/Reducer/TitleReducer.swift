//
//  TitleReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import DomainRealm
import Common
import CommonUI

import ComposableArchitecture

@Reducer
public struct TitleReducer {
    public struct State: Equatable {
        public var currentBible: TitleVO
        public var lastChapter: Int
        public var isPresent: Bool
        public var isPresentTitleSheet: Bool
        
        public static let initialState = State(
            currentBible: .initialState,
            lastChapter: 1,
            isPresent: false,
            isPresentTitleSheet: false
        )
    }
    
    public enum Action: FeatureAction {
        case view(ViewAction)
        case inner(InnerAction)
    }
    
    public enum ViewAction: Equatable {
        case presentTitle(Bool)
        case titleDidTapped
        case bibleTitleDidTapped(BibleTitle)
        case bibleChapterDidTapped(Int)
    }
    
    public enum InnerAction: Equatable {
        case selectDidFinish
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.presentTitle(isPresent)):
                state.isPresent = isPresent
                
            case .view(.titleDidTapped):
                break
                
            case .view(.bibleTitleDidTapped(let title)):
                state.lastChapter = title.lastChapter
                
            case .view(.bibleChapterDidTapped(let chapter)):
                Log.debug(chapter)
                
            case .inner(.selectDidFinish):
                Log.debug("\(state.currentBible.title) \(state.currentBible.chapter)장")
            }
            return .none
        }
    }
}
