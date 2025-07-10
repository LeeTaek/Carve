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
        public var drawings: [DrawingVO] = []

        public static let initialState = State(title: .init(title: .genesis, chapter: 1),
                                               section: 1)
        
        public init(title: TitleVO, section: Int) {
            self.id = "DrewHistory.\(title.title.rawValue).\(title.chapter).\(section)"
            self.title = title
            self.section = section
        }
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction {
        case view(View)
        case setDrawings([DrawingVO])
        case setPresentDrawing(DrawingVO)
        
        public enum View {
            case fetchDrawings
            case selectDrawing(DrawingVO)
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.fetchDrawings):
                let title = state.title
                let section = state.section
                return .run { send in
                    do {
                        guard let fetchedDrawings = try await drawingContext.fetchDrawings(title: title, section: section) else { return }
                        await send(.setDrawings(fetchedDrawings))
                    } catch  {
                        Log.error("fetched Drawing Data error", error)
                        await send(.setDrawings([]))
                    }
                }
            case .setDrawings(let drawings):
                state.drawings = drawings
            case .view(.selectDrawing(let drawing)):
                state.drawings.forEach {
                    $0.isPresent = ($0 == drawing)
                }
                return .run { [drawings = state.drawings] send in
                    try await drawingContext.updateDrawings(drawings: drawings)
                    await send(.setPresentDrawing(drawing))
                }
            default: break
            }
            return .none
        }
    }
}
