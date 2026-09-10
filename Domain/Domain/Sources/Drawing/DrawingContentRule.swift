//
//  DrawingContentRule.swift
//  Domain
//
//  Created by Claude on 9/10/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation

/// 행에 **획이 있는가** 를 판정하는 단일 기준 (설계 §8-7).
///
/// UI-2 의 "지우기" 는 행을 삭제하지 않는다 — 활성 행의 `lineData` 를 비우고 `updateDate` 를 `now` 로 찍으며
/// 원래 내용은 보관 행으로 옮긴다(보관 행의 `updateDate` 는 원래 필사 시각 그대로). 그래서 지우기를 한 절에는
/// **빈 활성 행**이 남고, 그 행이 `updateDate` 최신이라 히스토리 목록 맨 위에 온다. §8-7 의 처방이
/// "빈 행은 **히스토리 목록에서만** 숨긴다" 인 이유다.
///
/// ⚠️ **"목록에서만" 이 핵심이다.** 저장(`applyDrawingMutations`) · 대표 선택(`DrawingRepresentativeRule` ·
/// `mainDrawing()`) · 조회(`loadDrawingSnapshots`) 는 빈 행을 그대로 봐야 한다. 빈 활성 행이 대표로 남아야
/// 캔버스가 비어 보이고, 그 경로에서 걸러내면 과거 회차가 승격돼 **지운 획이 되살아난다** (§8-7 ★ 항목).
///
/// 이 판정을 쓰는 곳은 셋이고 전부 같은 기준이어야 한다:
///
/// | 부르는 곳 | 쓰임 |
/// |---|---|
/// | `Array<BibleDrawing>.historyRows()` | 히스토리 목록에서 빈 행을 숨긴다 |
/// | `ChapterCanvasFeature.menuAvailability(at:state:)` | "이전 필사 내용 보기" · "지우기" 를 띄울지 |
/// | `SwiftDatabaseActor.archiveAndResetVerseDrawing(_:chapter:now:)` | 보관본을 만들지 |
public enum DrawingContentRule {
    /// `lineData` 에 획이 하나라도 있는가.
    ///
    /// **길이로 판정하지 않는다.** 지우개로 전부 지운 절은 `lineData` 가 남아 있어도 stroke 가 0개이고,
    /// 반대로 빈 `Data` 는 유효한 PencilKit 인코딩이 아니라 디코딩 자체가 실패한다.
    /// - Parameter lineData: `PKDrawing.dataRepresentation()`. 비워진 행은 nil.
    /// - Returns: 디코딩되고 stroke 가 1개 이상이면 true.
    public static func hasStrokes(_ lineData: Data?) -> Bool {
        lineData?.containsPKStroke == true
    }
}

public extension Array where Element == BibleDrawing {
    /// 히스토리 목록에 보여 줄 행들 — **빈 행을 숨긴다** (§8-7).
    ///
    /// `fetchDrawings(chapter:verse:)` 가 준 정렬(`updateDate` 내림차순)을 그대로 유지한다. 걸러내기만 한다.
    ///
    /// - Important: 목록 표시 전용이다. 대표 선택이나 저장 경로에 끼워 넣지 말 것 — `DrawingContentRule` 의
    ///              경고를 보라.
    /// - Returns: 획이 있는 행들.
    func historyRows() -> [BibleDrawing] {
        filter { DrawingContentRule.hasStrokes($0.lineData) }
    }
}
