//
//  ChapterCanvasMenuAvailability.swift
//  FeatureCarve
//
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain

/// 롱프레스 지점의 절에서 **어떤 메뉴 항목을 띄울 수 있는지** (UI-2).
///
/// 할 수 없는 일을 메뉴에 남겨 두지 않는다 — 아무것도 쓰지 않은 절에 "지우기" 가 보이거나, 회차가 하나뿐인데
/// "이전 필사 내용 보기" 가 보이면 사용자는 눌러 보고서야 빈 결과를 만난다. 런북 D9-5-4 · 5-5 가
/// "회차가 쌓이지 않는 설계라 판정 불가" 로 남은 것도 같은 자리다 — 목록에 현재 필사 하나만 있는데
/// 이름은 "이전 필사" 였다.
struct ChapterCanvasMenuAvailability: Equatable {
    /// **내용이 있는**, 대표가 아닌 행이 하나 이상 있다 — 즉 목록에 실제로 그려질 지난 회차가 있다.
    let canViewHistory: Bool
    /// 대표 행의 현재 내용에 획이 있다. 저장분과 **대기 중인 편집**을 함께 본다.
    let canErase: Bool

    /// 띄울 항목이 하나도 없다. 이때는 메뉴 자체를 올리지 않는다.
    var isEmpty: Bool { !canViewHistory && !canErase }

    static let none = ChapterCanvasMenuAvailability(canViewHistory: false, canErase: false)
}

extension ChapterCanvasFeature {
    /// content 좌표가 가리키는 절의 메뉴 가용성.
    ///
    /// 편집 메뉴 구성은 **동기 콜백**(`UIEditMenuInteractionDelegate`)이라 DB 를 다녀올 수 없다. 다행히
    /// `loadDrawingSnapshots(chapter:)` 는 그 장의 **모든 행**을 주고 그대로 `loadedDrawings` 에 있으므로
    /// (대표만 걸러 오지 않는다) 두 판정 모두 메모리에서 끝난다.
    ///
    /// - Important: `canErase` 는 **저장분만 보면 안 된다.** 획을 하나 긋고 곧바로 롱프레스하면 그 획은 아직
    ///              `pendingMutations` 에 있고 `loadedDrawings` 에는 없다. 저장분만 보면 방금 쓴 절에서
    ///              "지우기" 가 사라진다.
    static func menuAvailability(at point: CGPoint, state: State) -> ChapterCanvasMenuAvailability {
        guard let verse = verse(at: point, state: state),
              let loaded = state.loadedDrawings else { return .none }

        let rows = loaded.filter { $0.verse == verse }
        let representative = rows.representative()

        // 지난 회차 — **내용이 있는** 대표 아닌 행. 지우기로 만들어진 보관본이 여기 걸린다.
        //
        // 목록(`historyRows()`)이 빈 행을 숨기므로 여기서도 같은 기준으로 세야 한다 (설계 §8-7). 행 존재만 보면
        // 어긋나는 자리가 있다 — 지우기 후 [빈 활성(대표), 보관본] 에서 사용자가 보관본을 고르면 보관본이
        // 대표가 되고 **빈 행이 비대표로** 남는다. 그때 메뉴는 항목을 띄우는데 목록은 비어 있다.
        let canViewHistory = rows.contains {
            $0.rowID != representative?.rowID && DrawingContentRule.hasStrokes($0.lineData)
        }

        return ChapterCanvasMenuAvailability(
            canViewHistory: canViewHistory,
            canErase: hasStrokes(verse: verse, representative: representative, state: state)
        )
    }

    /// 그 절의 현재 내용에 획이 있는가 — 대기 중인 편집이 있으면 그쪽이 이긴다.
    ///
    /// 빈 판정은 목록(`historyRows()`) · 저장소(`archiveAndResetVerseDrawing`)와 같은 `DrawingContentRule` 을 쓴다.
    /// 지우개로 전부 지운 절은 `lineData` 가 남아 있어도 stroke 가 0개라, 길이만 보면 틀린다.
    private static func hasStrokes(
        verse: Int,
        representative: VerseDrawingSnapshot?,
        state: State
    ) -> Bool {
        if let rowID = state.activeRowIDs[verse],
           let pending = state.pendingMutations[rowID] {
            switch pending.mutation {
            case .clear:
                return false
            case .replace(_, _, let data, _), .create(_, _, let data, _):
                return DrawingContentRule.hasStrokes(data)
            }
        }
        return DrawingContentRule.hasStrokes(representative?.lineData)
    }
}
