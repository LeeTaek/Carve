//
//  VerseDrawingHistoryFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import CarveToolkit
import CoreGraphics
import Domain

import ComposableArchitecture

@Reducer
public struct VerseDrawingHistoryFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Sendable {
        public var id: String
        /// 성경 제목, 장
        public var title: BibleChapter
        /// 성경 절
        public var verse: Int
        /// 해당 절에 대한 필사 기록 목록(행마다 스냅샷 하나)
        public var drawings: [VerseDrawingSnapshot] = []
        /// 목록을 한 번이라도 받았는지. 조회 전 빈 목록을 "기록 없음" 으로 깜빡이지 않게 한다.
        public var hasLoaded = false
        /// 롱탭한 절 행의 창 좌표(시안 E2 — 팝오버를 그 절 아래에 붙인다). 없으면 화면 가운데에 띄운다.
        public var anchorFrame: CGRect?
        /// 회차 바꾸기를 동기화 저장소에 쓰지 못한 사유(정책 §12-6 결정 1). 있으면 바꾸지 않았다는 안내를 띄운다.
        public var restoreBlock: SyncedWriteBlock?

        public static let initialState = State(title: .init(title: .genesis, chapter: 1),
                                               verse: 1)
        
        public init(title: BibleChapter, verse: Int) {
            self.id = "DrewHistory.\(title.title.rawValue).\(title.chapter).\(verse)"
            self.title = title
            self.verse = verse
        }
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.drawingEditEnvironment) var drawingEditEnvironment
    
    public enum Action: ViewAction {
        case view(View)
        /// 필사 기록 목록 비동기로 조회하여 반영
        case setDrawings([VerseDrawingSnapshot])
        /// 선택 여부를 상위로 전달: 팝업 닫기 위한 목적, 선택한 회차 전달
        case setPresentDrawing(VerseDrawingSnapshot)
        /// 고른 회차를 동기화 저장소에 써도 되는지 본 결과. 사유가 있으면 쓰지 않는다(정책 §12-6 결정 1).
        case restoreChecked(BibleDrawingRowID, SyncedWriteBlock?)
        
        public enum View {
            /// 성경 절에 대한 필사 기록을 가져옴
            case fetchDrawings
            /// 선택된 필사 내용을 Canvas에 main present로 설정(canvas에서 보일)
            case selectDrawing(VerseDrawingSnapshot)
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.fetchDrawings):
                state.restoreBlock = nil
                return fetchDrawings(state: &state)
                
            case .setDrawings(let drawings):
                // **빈 행은 목록에서만 숨긴다** (설계 §8-7 · `historyRows()`). 목록 상태에 들어오는 길목이 여기 하나뿐이라
                // 여기서 거르면 어떤 경로로 채워도 빈 행이 남지 않는다.
                //
                // UI-2 의 "지우기" 는 활성 행을 비우고 `updateDate` 를 `now` 로 찍는다. 거르지 않으면 지울 때마다
                // 목록 **맨 위**에 내용 없는 행이 와서 "불러올 수 없는 필사 데이터입니다." 로 그려지고 진짜 보관본이
                // 그 아래로 밀린다.
                //
                // ⚠️ 거르는 곳은 **목록뿐이다.** 저장소의 `fetchVerseSnapshots(chapter:verse:)` 는 그대로 둔다 —
                // 캔버스의 대표 선택(`DrawingRepresentativeRule`)과 `updatePresentDrawing(chapter:verse:presentRowID:)` 이 같은 행을 보고,
                // 거기서 빈 활성 행이 빠지면 대표가 과거 회차로 승격돼 지운 획이 되살아난다. 회차를 고를 때도
                // `updatePresentDrawing` 이 DB 의 **모든 행**을 다시 읽어 `isPresent` 를 옮기므로, 목록에서 뺀 빈 행의
                // 표시도 정상적으로 내려간다.
                //
                // 기준은 `Array<BibleDrawing>.historyRows()` 와 같은 `DrawingContentRule.hasStrokes(_:)` 다. 순서는 조회 그대로다.
                state.drawings = drawings.filter { DrawingContentRule.hasStrokes($0.lineData) }
                state.hasLoaded = true
                return .none
                
            case .view(.selectDrawing(let drawing)):
                // 회차 바꾸기는 동기화 저장소(`BibleDrawing.isPresent`)를 바꾼다 — 쓰기 직전에 소유를 확인한다.
                // 확인 결과에는 행 키만 싣고, 고를 행은 그때의 목록에서 다시 찾는다.
                let presentRowID = drawing.rowID
                return .run { [drawingEditEnvironment] send in
                    await send(.restoreChecked(presentRowID, SyncedWriteBlock.check(await drawingEditEnvironment.current())))
                }

            case let .restoreChecked(presentRowID, block):
                if let block {
                    Log.error("이전 필사 기록 — 동기화 저장소에 쓰지 않고 막았다", "\(block)")
                    state.restoreBlock = block
                    return .none
                }
                state.restoreBlock = nil
                guard let drawing = state.drawings.first(where: { $0.rowID == presentRowID }) else { return .none }
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
                let fetchedDrawings = try await drawingContext.fetchVerseSnapshots(chapter: title, verse: verse)
                await send(.setDrawings(fetchedDrawings))
            } catch {
                Log.error("fetched Drawing Data error", error)
                await send(.setDrawings([]))
            }
        }
    }
    
    /// 선택된 필사 기록을 현재 선택 상태로 표시하고, 대표 행을 갱신한 뒤 상위에 전달.
    /// - Parameters:
    ///   - state: 목록 상태. 고른 행만 `isPresent == true` 로 바꾼다(표시용).
    ///   - drawing: 고른 회차.
    /// - Returns: 저장소의 대표 행을 옮긴 뒤 `setPresentDrawing` 을 보내는 효과. 순서는 저장 → 알림이다.
    private func handleSelectDrawing(state: inout State, drawing: VerseDrawingSnapshot) -> Effect<Action> {
        // 로컬 상태에서 선택된 행만 isPresent = true 로 갱신
        state.drawings = state.drawings.map { $0.withPresent($0.rowID == drawing.rowID) }
        let title = state.title
        let verse = state.verse
        let presentRowID = drawing.rowID
        let selected = drawing.withPresent(true)
        // 저장이 끝난 뒤 상위에 알리는 순서는 그대로 둔다.
        return .concatenate(
            .run { _ in
                await drawingContext.updatePresentDrawing(
                    chapter: title,
                    verse: verse,
                    presentRowID: presentRowID
                )
            },
            .send(.setPresentDrawing(selected))
        )
    }
}

private extension VerseDrawingSnapshot {
    /// 대표 표시(`isPresent`)만 바꾼 사본. 스냅샷은 값이라 목록의 표시를 바꿀 때 새로 만든다.
    func withPresent(_ isPresent: Bool) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse,
            rowID: rowID,
            isPresent: isPresent,
            updateDate: updateDate,
            lineData: lineData,
            drawingVersion: drawingVersion,
            metadata: metadata
        )
    }
}
