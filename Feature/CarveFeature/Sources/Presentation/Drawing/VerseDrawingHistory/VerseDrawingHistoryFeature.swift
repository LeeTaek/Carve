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
public struct VerseDrawingHistoryFeature {
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        /// 성경 제목, 장
        public var title: BibleChapter
        /// 성경 절
        public var verse: Int
        /// 해당 절에 대한 필사 기록 목록
        public var drawings: [BibleDrawing] = []

        public static let initialState = State(title: .init(title: .genesis, chapter: 1),
                                               verse: 1)
        
        public init(title: BibleChapter, verse: Int) {
            self.id = "DrewHistory.\(title.title.rawValue).\(title.chapter).\(verse)"
            self.title = title
            self.verse = verse
        }
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction {
        case view(View)
        /// 필사 기록 목록 비동기로 조회하여 반영
        case setDrawings([BibleDrawing])
        /// 선택 여부를 상위로 전달: 팝업 닫기 위한 목적
        case setPresentDrawing
        
        public enum View {
            /// 성경 절에 대한 필사 기록을 가져옴
            case fetchDrawings
            /// 선택된 필사 내용을 Canvas에 main present로 설정(canvas에서 보일)
            case selectDrawing(BibleDrawing)
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.fetchDrawings):
                return fetchDrawings(state: &state)
                
            case .setDrawings(let drawings):
                state.drawings = drawings
                return .none
                
            case .view(.selectDrawing(let drawing)):
                return handleSelectDrawing(state: &state, drawing: drawing)
                
            default: return .none
            }
        }
    }
}

extension VerseDrawingHistoryFeature {
    /// 현재 절에 대한 필사 기록들을 비동기로 조회하고, 결과를 setDrawings 액션으로 반영.
    private func fetchDrawings(state: inout State) -> Effect<Action> {
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
    }
    
    /// 선택된 필사 기록을 현재 선택 상태로 표시하고, present ID를 갱신한 뒤 상위에 전달.
    private func handleSelectDrawing(state: inout State, drawing: BibleDrawing) -> Effect<Action> {
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
            await send(.setPresentDrawing)
        }
    }
}
