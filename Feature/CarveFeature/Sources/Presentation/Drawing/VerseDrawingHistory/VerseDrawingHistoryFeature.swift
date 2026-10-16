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
        /// 필사책과 장(번역본 포함). 조회 · 회차 바꾸기는 이 필사책 · 번역본의 행만 본다 — 같은 절의 다른 필사책 · 번역본 필사는 섞이지 않는다.
        public var page: NotebookChapter
        /// 성경 절
        public var verse: Int
        /// 목록에 보이는 필사 기록(행마다 스냅샷 하나) — 획 있는 행만, 같은 내용은 하나로 묶었다(`setDrawings`).
        public var drawings: [VerseDrawingSnapshot] = []
        /// 목록을 한 번이라도 받았는지. 조회 전 빈 목록을 "기록 없음" 으로 깜빡이지 않게 한다.
        public var hasLoaded = false
        /// 롱탭한 절 행의 창 좌표(시안 E2 — 팝오버를 그 절 아래에 붙인다). 없으면 화면 가운데에 띄운다.
        public var anchorFrame: CGRect?
        /// 회차 바꾸기를 동기화 저장소에 쓰지 못한 사유(정책 §12-6 결정 1). 있으면 바꾸지 않았다는 안내를 띄운다.
        public var restoreBlock: SyncedWriteBlock?

        /// 자리표시 — 미리보기 전용이라 기본 필사책으로 둔다(저장 경로가 아니다).
        public static let initialState = State(page: NotebookChapter(notebook: .default, chapter: .init(title: .genesis, chapter: 1)),
                                               verse: 1)

        /// - Parameters:
        ///   - page: 필사책과 장(번역본 포함). 기본값이 없다(필사책 결정 12) — 빠뜨리면 지금 필사책이 아닌 기본 필사책의 기록을 보인다.
        ///   - verse: 절 번호.
        public init(page: NotebookChapter, verse: Int) {
            // 권 이름은 행과 같은 `StoredBookKey` 로 짓는다 — 기본 필사책의 개역개정은 지금과 같고(`rawValue`), 영어는 번역본 접두,
            // 다른 필사책은 필사책 접두가 붙어 따로다.
            self.id = "DrewHistory.\(StoredBookKey.titleName(for: page)).\(page.chapter.chapter).\(verse)"
            self.page = page
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
                // ⚠️ 거르는 곳은 **목록뿐이다.** 저장소의 `fetchVerseSnapshots(page:verse:)` 는 그대로 둔다 —
                // 캔버스의 대표 선택(`DrawingRepresentativeRule`)과 `updatePresentDrawing(page:verse:presentRowID:)` 이 같은 행을 보고,
                // 거기서 빈 활성 행이 빠지면 대표가 과거 회차로 승격돼 지운 획이 되살아난다. 회차를 고를 때도
                // `updatePresentDrawing` 이 DB 의 **모든 행**을 다시 읽어 `isPresent` 를 옮기므로, 목록에서 뺀 빈 행의
                // 표시도 정상적으로 내려간다.
                //
                // 기준은 `Array<BibleDrawing>.historyRows()` 와 같은 `DrawingContentRule.hasStrokes(_:)` 다. 순서는 조회 그대로다.
                let carved = drawings.filter { DrawingContentRule.hasStrokes($0.lineData) }
                // **같은 내용의 행도 목록에서만 하나로 보인다** (정책 §7-3 — 두 기기가 오프라인으로 같은 백업을 불러오면 같은 내용 행이 둘 생긴다).
                // 남기는 행은 대표 규칙 순서라 지금 보이는 회차는 늘 남고, 회차 고르기도 남긴 행으로 한다. 저장소의 행은 그대로다
                // (`VerseDrawingHistoryDedup`). 남긴 행을 고르면 `updatePresentDrawing` 이 숨긴 같은 내용 행의 `isPresent` 도 함께 내린다.
                state.drawings = VerseDrawingHistoryDedup.visibleRows(carved)
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
                // 목록에는 남긴 행만 있다 — 같은 내용으로 숨긴 행은 고를 수 없다(`setDrawings`).
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
    /// 조회는 저장소가 주는 **모든 행** 그대로다. 빈 행을 거르고 같은 내용을 하나로 묶는 것은 `setDrawings` 한 곳이다 (§8-7 · 정책 §7-3).
    /// 저장소는 page(`state.page`)의 필사책 · 번역본 행만 준다 — KJV 장이면 KJV 행만, 두 번째 필사책이면 그 필사책 행만 보인다
    /// (영어 현지화 결정 1 · 필사책 §7 「이전 필사 보기는 필사책 안에서만」).
    private func fetchDrawings(state: inout State) -> Effect<Action> {
        let page = state.page
        let verse = state.verse
        return .run { send in
            do {
                let fetchedDrawings = try await drawingContext.fetchVerseSnapshots(page: page, verse: verse)
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
    ///   대표는 page(`state.page`)의 필사책 · 번역본 행 사이에서만 옮긴다 — 같은 절의 다른 필사책 · 번역본 대표는 그대로다.
    private func handleSelectDrawing(state: inout State, drawing: VerseDrawingSnapshot) -> Effect<Action> {
        // 로컬 상태에서 선택된 행만 isPresent = true 로 갱신
        state.drawings = state.drawings.map { $0.withPresent($0.rowID == drawing.rowID) }
        let page = state.page
        let verse = state.verse
        let presentRowID = drawing.rowID
        let selected = drawing.withPresent(true)
        // 저장이 끝난 뒤 상위에 알리는 순서는 그대로 둔다.
        return .concatenate(
            .run { _ in
                await drawingContext.updatePresentDrawing(
                    page: page,
                    verse: verse,
                    presentRowID: presentRowID
                )
            },
            .send(.setPresentDrawing(selected))
        )
    }
}

private extension VerseDrawingSnapshot {
    /// 대표 표시(`isPresent`)만 바꾼 사본. 스냅샷은 값이라 목록의 표시를 바꿀 때 새로 만든다 — 행의 번역본 · 필사책은 그대로 옮긴다.
    func withPresent(_ isPresent: Bool) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse,
            rowID: rowID,
            isPresent: isPresent,
            updateDate: updateDate,
            lineData: lineData,
            drawingVersion: drawingVersion,
            metadata: metadata,
            translation: translation,
            notebook: notebook
        )
    }
}
