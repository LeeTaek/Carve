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

import Dependencies

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
    private func verseDrawings(chapter: BibleChapter, verse: Int) throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
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
    ///   - chapter: 성경의 이름과 장.
    ///   - verse: 절 번호.
    /// - Returns: 행마다 하나, `updateDate` 최신순. 행 키는 `rowKey`(`rowUUID` 또는 business `id`)다.
    public func verseDrawingSnapshots(chapter: BibleChapter, verse: Int) throws -> [VerseDrawingSnapshot] {
        try verseDrawings(chapter: chapter, verse: verse).map { row in
            VerseDrawingSnapshot(
                verse: verse,
                rowID: BibleDrawingRowID(raw: row.rowKey),
                isPresent: row.isPresent ?? false,
                updateDate: row.updateDate,
                lineData: row.lineData,
                drawingVersion: row.drawingVersion,
                metadata: DrawingLayoutMetadata.decode(blob: row.layoutMetadataData)
            )
        }
    }

    /// 한 절에서 `presentRowID` 행만 대표(`isPresent == true`)로 두고 나머지는 내린 뒤 저장한다.
    /// - Parameters:
    ///   - chapter: 성경의 이름과 장.
    ///   - verse: 절 번호.
    ///   - presentRowID: 대표로 둘 행의 키.
    public func markPresentDrawing(chapter: BibleChapter, verse: Int, presentRowID: BibleDrawingRowID) throws {
        for row in try verseDrawings(chapter: chapter, verse: verse) {
            row.isPresent = (row.rowKey == presentRowID.raw)
        }
        try modelContext.save()
    }

    /// 한 절의 대표 행(`mainDrawing()` 규칙) ID. 행이 없으면 nil.
    public func mainDrawingID(chapter: BibleChapter, verse: Int) throws -> PersistentIdentifier? {
        try verseDrawings(chapter: chapter, verse: verse).mainDrawing()?.persistentModelID
    }

    /// 한 장의 행을 절 오름차순으로 읽는다 — N-Canvas 가 장을 열 때만 쓴다(`DrawingDatabase.fetchForLegacyCanvas(chapter:)`).
    /// - Parameter chapter: 성경의 이름과 장.
    /// - Returns: 모델 배열. 이행 중 예외(N-Canvas): N-Canvas 제거 때 지운다 — 룰북 swiftdata.md
    public func legacyCanvasDrawings(chapter: BibleChapter) throws -> UncheckedSendable<[BibleDrawing]> {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapterNumber
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: [BibleDrawing] = try fetch(descriptor)
        // 이행 중 예외(N-Canvas): N-Canvas 제거 때 지운다 — 룰북 swiftdata.md
        return UncheckedSendable(storedDrawing)
    }

    // MARK: 필사 활동

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
