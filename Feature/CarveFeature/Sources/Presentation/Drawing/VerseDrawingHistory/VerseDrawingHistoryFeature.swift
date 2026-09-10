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
        /// 선택 여부를 상위로 전달: 팝업 닫기 위한 목적, 선택한 drawing 전달
        case setPresentDrawing(BibleDrawing)
        
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
                // **빈 행은 목록에서만 숨긴다** (설계 §8-7 · `historyRows()`). 목록 상태에 들어오는 길목이 여기 하나뿐이라
                // 여기서 거르면 어떤 경로로 채워도 빈 행이 남지 않는다.
                //
                // UI-2 의 "지우기" 는 활성 행을 비우고 `updateDate` 를 `now` 로 찍는다. 거르지 않으면 지울 때마다
                // 목록 **맨 위**에 내용 없는 행이 와서 "불러올 수 없는 필사 데이터입니다." 로 그려지고 진짜 보관본이
                // 그 아래로 밀린다.
                //
                // ⚠️ 거르는 곳은 **목록뿐이다.** 저장소의 `fetchDrawings(chapter:verse:)` 는 그대로 둔다 —
                // `updateDrawings(requests:)` 와 `updatePresentDrawing(chapter:verse:presentID:)` 이 같은 조회를 쓰고,
                // 거기서 빈 활성 행이 빠지면 대표가 과거 회차로 승격돼 지운 획이 되살아난다. 회차를 고를 때도
                // `updatePresentDrawing` 이 DB 의 **모든 행**을 다시 읽어 `isPresent` 를 옮기므로, 목록에서 뺀 빈 행의
                // 표시도 정상적으로 내려간다.
                state.drawings = drawings.historyRows()
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
    ///
    /// 조회는 저장소가 주는 **모든 행** 그대로다. 빈 행을 거르는 것은 `setDrawings` 한 곳이다 (§8-7).
    private func fetchDrawings(state: inout State) -> Effect<Action> {
        let title = state.title
        let verse = state.verse
        return .run { send in
            do {
                let fetchedDrawings = try await drawingContext.fetchDrawings(chapter: title, verse: verse)
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
                chapter: title,
                verse: verse,
                presentID: presentID
            )
            await send(.setPresentDrawing(drawing))
        }
    }
}
