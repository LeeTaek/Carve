//
//  BibleTitleDrawingRecord.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 성경 한 권의 장별 필사 기록 요약. 탐색 장 목록이 필사한 장을 칠하고 기본 장을 고를 때 쓴다.
///
/// 획이 있는지는 `DrawingContentRule` 로 판정한다. 조회는 `DrawingDatabase.fetchDrawingRecord(title:)` 다.
public struct BibleTitleDrawingRecord: Sendable, Equatable {
    /// 획이 있는 필사 행이 하나라도 남은 장.
    public var drawnChapters: Set<Int>
    /// 획이 있는 필사 중 `updateDate` 가 가장 최근인 장. 기록이 없으면 nil.
    public var latestChapter: Int?

    public init(drawnChapters: Set<Int> = [], latestChapter: Int? = nil) {
        self.drawnChapters = drawnChapters
        self.latestChapter = latestChapter
    }
}
