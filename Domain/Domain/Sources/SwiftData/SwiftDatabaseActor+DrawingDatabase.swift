//
//  SwiftDatabaseActor+DrawingDatabase.swift
//  Domain
//
//  `DrawingDatabase` 의 조회를 actor 안에서 값으로 옮긴다 — @Model 은 actor 밖으로 넘기지 않는다(룰북 swiftdata.md 규칙 3 · 4).
//  조건 · 정렬은 옛 `DrawingDatabase` 조회 그대로다.
//

import CarveToolkit
import Foundation
import SwiftData

/// 장 단위 필사(`BiblePageDrawing`) 한 행의 값. 모델을 actor 밖으로 넘기지 않으려고 옮긴다.
///
/// 장 단위 경로는 호출부가 없다(`DrawingDatabase.upsertPageDrawing` 주석) — 시험만 읽는다.
public struct BiblePageDrawingSnapshot: Equatable, Sendable {
    /// 페이지 전체 기준 `PKDrawing.dataRepresentation()`.
    public let fullLineData: Data?
    /// 마지막으로 고친 시각.
    public let updateDate: Date?
}

extension SwiftDatabaseActor {
    // MARK: 절 단위 행

    /// 한 절의 행 — `updateDate` 최신순이다(`DrawingDatabase.fetchVerseSnapshots(chapter:verse:)` 가 이 조건 · 정렬로 읽는다).
    ///
    /// 장의 번역본 행만 읽는다 — 술어의 `titleName` 은 `StoredBookKey.titleName(for:)` 다(개역개정은 열이 nil 인 옛 행 포함).
    private func verseDrawings(chapter: BibleChapter, verse: Int) throws -> [BibleDrawing] {
        let titleName = StoredBookKey.titleName(for: chapter)
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapterNumber
            && $0.verse == verse
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.updateDate, order: .reverse)])
        let storedDrawing: [BibleDrawing] = try fetch(descriptor)
        Log.debug("Drew Log Count:", storedDrawing.count)
        return storedDrawing
    }

    /// 한 절의 모든 행을 스냅샷으로 읽는다 — 이력 화면용.
    /// - Parameters:
    ///   - chapter: 성경의 이름과 장(번역본 포함). 그 번역본의 행만 읽는다.
    ///   - verse: 절 번호.
    /// - Returns: 행마다 하나, `updateDate` 최신순. 행 키는 `rowKey`(`rowUUID` 또는 business `id`)다.
    public func verseDrawingSnapshots(chapter: BibleChapter, verse: Int) throws -> [VerseDrawingSnapshot] {
        try verseDrawings(chapter: chapter, verse: verse).compactMap(VerseDrawingSnapshot.init(drawing:))
    }

    /// 한 절에서 `presentRowID` 행만 대표(`isPresent == true`)로 두고 나머지는 내린 뒤 저장한다.
    ///
    /// 장의 번역본 행만 바꾼다 — 같은 권 · 장 · 절의 다른 번역본 행의 `isPresent` 는 그대로다.
    /// - Parameters:
    ///   - chapter: 성경의 이름과 장(번역본 포함).
    ///   - verse: 절 번호.
    ///   - presentRowID: 대표로 둘 행의 키.
    public func markPresentDrawing(chapter: BibleChapter, verse: Int, presentRowID: BibleDrawingRowID) throws {
        for row in try verseDrawings(chapter: chapter, verse: verse) {
            row.isPresent = (row.rowKey == presentRowID.raw)
        }
        try modelContext.save()
    }

    // MARK: 필사 활동
    //
    // 차트 · 최근 기록은 `updateDate` 로만 거르고 **모든 번역본**의 행을 읽는다. 행의 번역본은 `DrawingActivity.chapter` 가 푼다.

    /// 기간 안에 고친 행의 활동 — `updateDate` 최신순이다. 고친 시각이 없는 행은 빠진다.
    /// - Parameter range: 조회 기간(시작 포함, 끝 제외).
    public func drawingActivities(in range: DateInterval) throws -> [DrawingActivity] {
        let predicate = #Predicate<BibleDrawing> {
            if let updateDate = $0.updateDate {
                return updateDate >= range.start && updateDate < range.end
            } else {
                return false
            }
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updateDate, order: .reverse)]
        )
        let rows: [BibleDrawing] = try fetch(descriptor)
        return rows.map(DrawingActivity.init(drawing:))
    }

    /// 최근에 고친 행의 활동 — `updateDate` 최신순으로 `limit` 개까지다.
    /// - Parameter limit: 최대 개수. 0 보다 커야 한다.
    public func recentDrawingActivities(limit: Int) throws -> [DrawingActivity] {
        let predicate = #Predicate<BibleDrawing> {
            $0.updateDate != nil
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updateDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let rows: [BibleDrawing] = try fetch(descriptor)
        return rows.map(DrawingActivity.init(drawing:))
    }

    /// 두 시각 사이(양 끝 포함)에 고친 행의 활동. 정렬하지 않는다.
    public func drawingActivities(from start: Date, through end: Date) throws -> [DrawingActivity] {
        let predicate = #Predicate<BibleDrawing> {
            if let updateDate = $0.updateDate {
                return updateDate >= start && updateDate <= end
            } else {
                return false
            }
        }
        let rows: [BibleDrawing] = try fetch(FetchDescriptor(predicate: predicate))
        return rows.map(DrawingActivity.init(drawing:))
    }

    // MARK: 장 단위 행

    /// 한 장의 장 단위 행 — 조건에 맞는 첫 행이다(정렬 없음).
    private func pageDrawing(chapter: BibleChapter) throws -> BiblePageDrawing? {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BiblePageDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapterNumber
        }
        let stored: [BiblePageDrawing] = try fetch(FetchDescriptor(predicate: predicate))
        return stored.first
    }

    /// 한 장의 장 단위 행 값. 없으면 nil.
    public func pageDrawingSnapshot(chapter: BibleChapter) throws -> BiblePageDrawingSnapshot? {
        try pageDrawing(chapter: chapter).map { BiblePageDrawingSnapshot(fullLineData: $0.fullLineData, updateDate: $0.updateDate) }
    }

    /// 한 장의 장 단위 행 ID. 없으면 nil.
    public func pageDrawingID(chapter: BibleChapter) throws -> PersistentIdentifier? {
        try pageDrawing(chapter: chapter)?.persistentModelID
    }
}

// MARK: - 행 → 스냅샷

extension VerseDrawingSnapshot {
    /// 필사 행을 스냅샷으로 옮긴다. actor 안에서만 부른다(@Model 은 actor 밖으로 나가지 않는다).
    ///
    /// 번역본은 행의 `titleName` 을 `StoredBookKey.decode` 로 푼 값이다 — 접두가 없으면 `translation` 열이 nil 이든 `.NKRV` 든 개역개정이다.
    /// 절 번호가 없거나 `titleName` 을 풀지 못하는 행(모르는 권 이름)은 nil 이다 — 호출부는 건너뛴다.
    /// 조회 술어가 `StoredBookKey.titleName(for:)` 로 거르므로 장 조회에서 푸는 데 실패하는 행은 없다.
    init?(drawing row: BibleDrawing) {
        guard let verse = row.verse,
              let titleName = row.titleName,
              let key = StoredBookKey.decode(titleName) else { return nil }
        self.init(
            verse: verse,
            rowID: BibleDrawingRowID(raw: row.rowKey),
            isPresent: row.isPresent ?? false,
            updateDate: row.updateDate,
            lineData: row.lineData,
            drawingVersion: row.drawingVersion,
            metadata: DrawingLayoutMetadata.decode(blob: row.layoutMetadataData),
            translation: key.translation
        )
    }
}
