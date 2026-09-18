//
//  ChapterCanvasMenuAvailability.swift
//  CarveFeature
//
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation

/// 롱프레스 지점의 절에서 **어떤 메뉴 항목을 띄울 수 있는지** (UI-2).
///
/// 할 수 없는 일을 메뉴에 남겨 두지 않는다 — 아무것도 쓰지 않은 절에 "지우기" 가 보이거나, 회차가 하나뿐인데
/// "이전 필사 내용 보기" 가 보이면 사용자는 눌러 보고서야 빈 결과를 만난다. 런북 D9-5-4 · 5-5 가
/// "회차가 쌓이지 않는 설계라 판정 불가" 로 남은 것도 같은 자리다 — 목록에 현재 필사 하나만 있는데
/// 이름은 "이전 필사" 였다.
///
/// 「즐겨찾기」(시안 N1)는 절만 찾으면 **언제나** 할 수 있다 — 필기 없는 말씀도 즐겨찾기한다. 그래서 2026-09-15 부터
/// 합성된 장의 절이면 메뉴가 늘 열리고, 「이전 필사 내용 보기」 · 「지우기」 만 조건에 따라 빠진다.
struct ChapterCanvasMenuAvailability: Equatable {
    /// 절을 찾았다 — 즐겨찾기에 추가하거나 해제할 수 있다.
    let canFavorite: Bool
    /// **내용이 있는**, 대표가 아닌 행이 하나 이상 있다 — 즉 목록에 실제로 그려질 지난 회차가 있다.
    let canViewHistory: Bool
    /// 대표 행의 현재 내용에 획이 있다. 저장분과 **대기 중인 편집**을 함께 본다.
    let canErase: Bool

    /// 띄울 항목이 하나도 없다 — 절을 찾지 못한 자리다. 이때는 메뉴 자체를 올리지 않는다.
    var isEmpty: Bool { !canFavorite && !canViewHistory && !canErase }

    static let none = ChapterCanvasMenuAvailability(canFavorite: false, canViewHistory: false, canErase: false)
}

extension ChapterCanvasFeature {
    /// content 좌표가 가리키는 절. 표시 중인 레이아웃(합성 시점 값)으로 찾고, 텍스트 쪽(컬럼 왼쪽)을 눌러도
    /// 같은 행이 되도록 x 만 컬럼 안으로 당긴다 (§20-11). 합성 전이거나 세로로 벗어나면 nil.
    static func verse(at point: CGPoint, state: State) -> Int? {
        guard state.isInputEnabled, let layout = state.renderedLayout else { return nil }
        let origin = state.renderedColumnOrigin
        let layoutPoint = CGPoint(
            x: min(max(point.x - origin.x, 0), layout.writingWidth),
            y: point.y - origin.y
        )
        return layout.verse(containing: layoutPoint)
    }

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

        // 지우기(보관 후 초기화)와 기록 복원은 저장소 행을 바꾼다. 귀속할 근거가 없는 세션, 보이기만 하는 초안을 이은 절은 저장소에 쓰지 않으므로
        // 띄우지 않는다 — 초안에만 있는 필기를 두고 저장소 행만 바꾸면 다시 읽을 때 초안이 되살아나 지운 절이 돌아온다(§12-6 구현 순서 ②,
        // ③ 에서 버전으로 되살린다). 폐기 가능한 데이터로 시험하는 중간 빌드에서만 받아들이는 공백이다 — 출시 전에 되살리거나 사유를 보인다.
        let writesStore = state.writesStore(verse: verse)
        return ChapterCanvasMenuAvailability(
            canFavorite: true,
            canViewHistory: writesStore && canViewHistory,
            canErase: writesStore && currentInkSnapshot(verse: verse, representative: representative, state: state) != nil
        )
    }

    /// 그 절의 지금 필기 — 대기 중인 편집이 있으면 그쪽이 이긴다. 획이 없으면 nil.
    ///
    /// 「지우기」 가용성과 「즐겨찾기에 추가」 가 보존하는 필기가 같은 판정을 쓴다 — 방금 쓴 획이 저장 전이어도 포함된다.
    /// - Parameters:
    ///   - verse: 절 번호.
    ///   - state: Feature 상태.
    static func currentInk(verse: Int, state: State) -> Data? {
        currentInkSnapshot(verse: verse, state: state)?.lineData
    }

    /// 그 절의 지금 필기를 담은 **행** — `currentInk` 와 같은 판정이다. 획이 없으면 nil.
    ///
    /// 절 이미지(시안 G1)는 좌표 형식(`drawingVersion` · metadata)까지 알아야 필기를 현재 밑줄에 맞춰 그릴 수 있어 행을 쓴다.
    /// 대기 중인 편집은 저장소에 기록될 모습 그대로 만든다 — 편집은 늘 현재 레이아웃 기준 v3 로 저장된다(`DrawingCodec.mutations`).
    /// - Parameters:
    ///   - verse: 절 번호.
    ///   - state: Feature 상태.
    static func currentInkSnapshot(verse: Int, state: State) -> VerseDrawingSnapshot? {
        guard let loaded = state.loadedDrawings else { return nil }
        let representative = loaded.filter { $0.verse == verse }.representative()
        return currentInkSnapshot(verse: verse, representative: representative, state: state)
    }

    /// 빈 판정은 목록(`historyRows()`) · 저장소(`archiveAndResetVerseDrawing`)와 같은 `DrawingContentRule` 을 쓴다.
    /// 지우개로 전부 지운 절은 `lineData` 가 남아 있어도 stroke 가 0개라, 길이만 보면 틀린다.
    private static func currentInkSnapshot(
        verse: Int,
        representative: VerseDrawingSnapshot?,
        state: State
    ) -> VerseDrawingSnapshot? {
        let snapshot: VerseDrawingSnapshot?
        if let rowID = state.activeRowIDs[verse],
           let pending = state.pendingMutations[rowID] {
            switch pending.mutation {
            case .clear:
                snapshot = nil
            case let .replace(_, pendingRowID, pendingData, metadata), let .create(_, pendingRowID, pendingData, metadata):
                snapshot = VerseDrawingSnapshot(
                    verse: verse, rowID: pendingRowID, isPresent: true, updateDate: nil,
                    lineData: pendingData, drawingVersion: 3, metadata: metadata
                )
            }
        } else {
            snapshot = representative
        }
        guard let snapshot, DrawingContentRule.hasStrokes(snapshot.lineData) else { return nil }
        return snapshot
    }
}
