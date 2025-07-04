//
//  SentenceDrewHistoryListReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Domain

import ComposableArchitecture

@Reducer
public struct SentenceDrewHistoryListReducer {
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var title: TitleVO
        public var section: Int

        public static let initialState = State(title: .init(title: .genesis, chapter: 1),
                                               section: 1)
        
        public init(title: TitleVO, section: Int) {
            self.id = "DrewHistory.\(title.title.rawValue).\(title.chapter).\(section)"
            self.title = title
            self.section = section
        }
    }
    
    public enum Action: ViewAction {
        case view(View)
        
        public enum View {
            
        }
    }
    public var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
