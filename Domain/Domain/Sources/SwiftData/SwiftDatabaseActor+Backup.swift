//
//  SwiftDatabaseActor+Backup.swift
//  Domain
//
//  필사 백업 전용 조회 — `BibleDrawing` 행을 원본 필드 · 원본 바이트 그대로(`BackupRowRecord`) 읽는다 (설계 docs/backup-import-design.md §5-3).
//
//  `DrawingRepository.load`(`VerseDrawingSnapshot`)를 쓰지 않는다 — 만든 시각 · 번역 저장값(nil 포함) · `rowUUID` 와 business id 구분 ·
//  `isPresent` 원본이 없고 메타데이터가 이미 해석돼 있어 원본 보존 계약을 지킬 수 없다. 내보내기 · 불러오기 판정 · 복원 쓰기가 이 파일의
//  **같은 변환**(`BibleDrawing.backupRecord`)으로 견준다 — 지문이 한쪽만 다시 인코딩되면 같은 필기를 다른 것으로 본다.
//

import CarveToolkit
import Foundation
import SwiftData

extension SwiftDatabaseActor {
    /// 행이 있는 장 — 권 순서(`BibleTitle.allCases`) → 장 순서.
    ///
    /// 권 이름이 `BibleTitle` 에 없거나 장이 없는 행은 어느 장에도 들지 않는다 — 절 키(권 코드 · 장)를 만들 수 없어 백업에 담지 못한다
    /// (편집 화면 · 이력 화면에도 보이지 않는 행이다). 그런 행이 있으면 수만 로그에 남긴다.
    /// - Returns: 장 목록. 부작용 없음(읽기만 한다).
    public func backupChapters() throws -> [BibleChapter] {
        try backupChapterList().chapters
    }

    /// 한 장의 모든 행(현재 · 보관 · 비운 행)과 지금 저장소 세대를 **같은 actor 구간에서** 읽는다(`BackupRowLoad`).
    ///
    /// 따로 읽으면 그 사이의 「모든 필사 삭제」 를 놓친다. 행은 절 → 행 키 순이다(같은 저장소면 같은 순서). 절 번호가 없는 행은
    /// 절 키를 만들 수 없어 빠진다 — 장 조회(`loadDrawingSnapshots`)도 그 행을 보이지 않는다.
    /// - Parameter chapter: 읽을 장.
    /// - Returns: 그 장의 행 원본과 세대. 부작용 없음(읽기만 한다).
    public func backupRows(chapter: BibleChapter) throws -> BackupRowLoad {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber
        }
        let rows: [BibleDrawing] = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        let records = rows.compactMap(\.backupRecord)
        if records.count < rows.count {
            Log.error("백업 — 절 번호가 없는 행은 담지 못한다", "\(titleName).\(chapterNumber)", "행 수=\(rows.count - records.count)")
        }
        return BackupRowLoad(
            rows: records.sorted { ($0.verse, $0.rowKey) < ($1.verse, $1.rowKey) },
            generation: DrawingStoreGeneration(raw: drawingStoreGeneration)
        )
    }

    /// 행이 있는 장과 그 목록을 읽은 때의 저장소 세대 — **같은 actor 구간**. 내보내기가 첫 장을 읽기 전의 「모든 필사 삭제」 도 잡는다.
    ///
    /// 권 · 장 두 속성만 읽는다(잉크 바이트를 메모리에 올리지 않는다).
    /// - Returns: 권 순서 → 장 순서의 장 목록과 세대. 부작용 없음(읽기만 한다).
    func backupChapterList() throws -> (chapters: [BibleChapter], generation: DrawingStoreGeneration) {
        var descriptor = FetchDescriptor<BibleDrawing>()
        descriptor.propertiesToFetch = [\.titleName, \.titleChapter]
        let rows: [BibleDrawing] = try modelContext.fetch(descriptor)
        var chapters: Set<BibleChapter> = []
        var unplaced = 0
        for row in rows {
            guard let name = row.titleName, let title = BibleTitle(rawValue: name), let chapter = row.titleChapter else {
                unplaced += 1
                continue
            }
            chapters.insert(BibleChapter(title: title, chapter: chapter))
        }
        if unplaced > 0 {
            Log.error("백업 — 권 · 장을 알 수 없는 행은 담지 못한다", "행 수=\(unplaced)")
        }
        return (chapters.sorted(by: BibleChapter.backupOrder), DrawingStoreGeneration(raw: drawingStoreGeneration))
    }
}

extension DrawingSchemaV4.BibleDrawing {
    /// 이 행의 원본 그대로 — 백업 전용 조회의 **유일한 변환**이다(내보내기 · 불러오기 판정 · 복원 쓰기가 함께 쓴다).
    ///
    /// 바이트 · `drawingVersion` · 시각 · 번역 저장값 · `isPresent` 를 바꾸지 않는다. 번역이 없으면 nil 그대로다(NKRV 로 채우지 않는다).
    /// 권 이름 · 장 · 절이 없는 행은 절 키를 만들 수 없어 nil 이다.
    var backupRecord: BackupRowRecord? {
        guard let titleName, let titleChapter, let verse else { return nil }
        // `id` 는 문맥에 따라 `PersistentIdentifier` 로도 읽힌다 — 타입을 적어 business id(`String!`)를 고른다(`rowKey` 와 같다).
        let businessID: String? = id
        return BackupRowRecord(
            rowUUID: rowUUID,
            businessID: businessID,
            titleName: titleName,
            chapter: titleChapter,
            verse: verse,
            translation: translation?.rawValue,
            isPresent: isPresent,
            creationDate: creationDate,
            updateDate: updateDate,
            drawingVersion: drawingVersion,
            lineData: lineData,
            layoutMetadataData: layoutMetadataData
        )
    }
}
