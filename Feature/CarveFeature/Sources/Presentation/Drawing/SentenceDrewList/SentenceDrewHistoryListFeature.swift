//
//  SentenceDrewHistoryListFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import CarveToolkit
import Domain

import ComposableArchitecture

@Reducer
public struct SentenceDrewHistoryListFeature {
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var title: TitleVO
        public var verse: Int
        public var drawings: [BibleDrawing] = []

        public static let initialState = State(title: .init(title: .genesis, chapter: 1),
                                               verse: 1)
        
        public init(title: TitleVO, verse: Int) {
            self.id = "DrewHistory.\(title.title.rawValue).\(title.chapter).\(verse)"
            self.title = title
            self.verse = verse
        }
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction {
        case view(View)
        case setDrawings([BibleDrawing])
        case setPresentDrawing(BibleDrawing)
        
        public enum View {
            case fetchDrawings
            case selectDrawing(BibleDrawing)
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.fetchDrawings):
                let title = state.title
                let verse = state.verse
                return .run { send in
                    do {
                        let fetchedDrawings = try await drawingContext.fetchDrawings(title: title, verse: verse)
                        await send(.setDrawings(fetchedDrawings))
                    } catch {
                        Log.error("fetched Drawing Data error", error)
                        await send(.setDrawings([]))
                    }
                }
            case .setDrawings(let drawings):
                state.drawings = drawings
            case .view(.selectDrawing(let drawing)):
                // 로컬 상태에서 선택된 drawing만 isPresent = true 로 갱신
                for index in state.drawings.indices {
                    state.drawings[index].isPresent = (state.drawings[index] == drawing)
                }
                let title = state.title
                let verse = state.verse
                let presentID = drawing.persistentModelID
                return .run { send in
                    await drawingContext.updatePresentDrawing(
                        title: title,
                        verse: verse,
                        presentID: presentID
                    )
                    await send(.setPresentDrawing(drawing))
                }
            default: break
            }
            return .none
        }
    }
}
