//
//  SwiftDataDrawingActivityRepository.swift
//  Domain
//
//  Created by Claude on 9/28/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// `DrawingActivityRepository` 의 SwiftData 구현.
///
/// 쿼리는 새로 쓰지 않고 `DrawingDatabase` 의 조회를 그대로 부른다 — 정렬 · 범위 조건이 기존 차트와 같다.
/// 스냅샷으로 옮기는 일은 actor 안에서 한다(`SwiftDatabaseActor.drawingActivities(in:)` 등). 모델은 actor 밖으로 나오지 않는다.
public struct SwiftDataDrawingActivityRepository: DrawingActivityRepository {
    private let database: DrawingDatabase

    /// - Parameter database: 사용할 조회 경로. 생략하면 현재 의존성의 `drawingData`.
    public init(database: DrawingDatabase? = nil) {
        if let database {
            self.database = database
        } else {
            @Dependency(\.drawingData) var injected
            self.database = injected
        }
    }

    public func activities(in range: DateInterval) async throws -> [DrawingActivity] {
        try await database.fetchDrawings(in: range)
    }

    public func recentActivities(limit: Int) async throws -> [DrawingActivity] {
        try await database.fetchRecentDrawings(limit: limit)
    }
}

extension DrawingActivity {
    /// 필사 행에서 차트가 읽는 값만 옮긴다. actor 안에서만 부른다.
    init(drawing: BibleDrawing) {
        self.init(
            updateDate: drawing.updateDate,
            titleName: drawing.titleName,
            titleChapter: drawing.titleChapter,
            verse: drawing.verse
        )
    }
}
