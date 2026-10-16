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
//  장은 필사책 · 번역본까지 포함한다(`NotebookChapter` — 영어 현지화 결정 1 · 2.2 필사책 결정 1). 장의 행은
//  `StoredBookKey.titleName(for: page)` 로 고르므로 한 장의 행은 한 필사책 · 한 번역본뿐이고, 영어 행(`KJV-…` · `BSB-…`, 열은 nil)이나
//  다른 필사책 행(`nb_<토큰>~…`)이 섞이지 않는다. 장 목록의 필사책 · 번역본은 `titleName` 접두로 정한다(`StoredBookKey.decodeRow`).
//  필사책 메타데이터(`DrawingNotebook`)도 여기서 원본 그대로(`BackupNotebookRecord`) 읽는다 — 쓰기는 `SwiftDataDrawingRepository+BackupRestore.swift`.
//

import CarveToolkit
import Foundation
import SwiftData

/// 내보내기가 처음에 한 번 읽는 저장소 목록 — 행이 있는 장 · 필사책 목록 · 저장소 세대를 **같은 actor 구간에서** 읽은 값.
struct BackupStoreListing: Sendable {
    /// 행이 있는 장(필사책 · 번역본 포함) — 필사책(기본 먼저) → 권 순서 → 장 순서 → 번역본 순서.
    /// 내보내기가 자리 목록으로 바꾼 값(`LiveBackupExporter`)은 번역본을 개역개정으로 맞춘 필사책 · 권 · 장 자리다.
    let pages: [NotebookChapter]
    /// 필사책 목록 — 필사책마다 하나(`BackupNotebookRecord.latestPerNotebook`).
    let notebooks: [BackupNotebookRecord]
    /// 읽은 때의 저장소 세대.
    let generation: DrawingStoreGeneration
}

extension SwiftDatabaseActor {
    /// 행이 있는 장(필사책 · 번역본 포함) — 필사책(기본 먼저 · 나머지 토큰 순) → 권 순서(`BibleTitle.allCases`) → 장 순서 → 번역본 순서.
    ///
    /// 장의 필사책 · 번역본은 `titleName` 접두로 정한다(`StoredBookKey.decodeRow` — 영어 행은 열이 nil 이어도 KJV · BSB 장이다).
    /// 권 이름을 풀 수 없거나 장이 없는 행은 어느 장에도 들지 않는다 — 절 키(권 코드 · 장)를 만들 수 없어 백업에 담지 못한다
    /// (편집 화면 · 이력 화면에도 보이지 않는 행이다). 그런 행이 있으면 수만 로그에 남긴다.
    /// - Returns: 장 목록. 부작용 없음(읽기만 한다).
    public func backupPages() throws -> [NotebookChapter] {
        try backupListing().pages
    }

    /// 한 장의 모든 행(현재 · 보관 · 비운 행)과 지금 저장소 세대를 **같은 actor 구간에서** 읽는다(`BackupRowLoad`).
    ///
    /// 따로 읽으면 그 사이의 「모든 필사 삭제」 를 놓친다. 행은 절 → 행 키 순이다(같은 저장소면 같은 순서). 절 번호가 없는 행은
    /// 절 키를 만들 수 없어 빠진다 — 장 조회(`loadDrawingSnapshots`)도 그 행을 보이지 않는다.
    /// 행은 그 장의 필사책 · 번역본 `titleName`(`StoredBookKey.titleName(for: page)`)으로 고른다 — 다른 필사책 · 번역본의 같은 권 · 장 행은 들지 않는다.
    /// - Parameter page: 읽을 장(필사책 · 번역본 포함).
    /// - Returns: 그 장의 행 원본과 세대. 부작용 없음(읽기만 한다).
    public func backupRows(page: NotebookChapter) throws -> BackupRowLoad {
        let titleName = StoredBookKey.titleName(for: page)
        let chapterNumber = page.chapter.chapter
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

    /// 행이 있는 장 · 필사책 목록 · 그 목록을 읽은 때의 저장소 세대 — **같은 actor 구간**. 내보내기가 첫 장을 읽기 전의 「모든 필사 삭제」 도 잡는다.
    ///
    /// 행은 권 · 장 두 속성만 읽는다(잉크 바이트를 메모리에 올리지 않는다). 필사책 · 번역본은 `titleName` 접두로 정한다(열을 읽지 않는다).
    /// - Returns: 장 목록(필사책 → 권 → 장 → 번역본 순) · 필사책 목록 · 세대. 부작용 없음(읽기만 한다).
    func backupListing() throws -> BackupStoreListing {
        var descriptor = FetchDescriptor<BibleDrawing>()
        descriptor.propertiesToFetch = [\.titleName, \.titleChapter]
        let rows: [BibleDrawing] = try modelContext.fetch(descriptor)
        var pages: Set<NotebookChapter> = []
        var unplaced = 0
        for row in rows {
            guard let name = row.titleName, let key = StoredBookKey.decodeRow(name), let chapter = row.titleChapter else {
                unplaced += 1
                continue
            }
            pages.insert(key.page(chapter: chapter))
        }
        if unplaced > 0 {
            Log.error("백업 — 권 · 장을 알 수 없는 행은 담지 못한다", "행 수=\(unplaced)")
        }
        return BackupStoreListing(
            pages: pages.sorted(by: NotebookChapter.backupOrder),
            notebooks: try backupNotebookRecords(),
            generation: DrawingStoreGeneration(raw: drawingStoreGeneration)
        )
    }

    /// 필사책 메타데이터 — `DrawingNotebook` 레코드를 원본 그대로 읽어 필사책마다 하나로 줄인다(같은 ID 가 둘 이상이면 `updatedAt` 이 늦은 것).
    ///
    /// `notebookID` 가 `NotebookID` 형식이 아닌 레코드는 담지 않고 수만 로그에 남긴다(어느 필사책인지 알 수 없다).
    /// - Returns: 필사책 목록(기본 먼저 · 나머지 토큰 순). 부작용 없음(읽기만 한다).
    func backupNotebookRecords() throws -> [BackupNotebookRecord] {
        let stored: [DrawingNotebook] = try modelContext.fetch(FetchDescriptor<DrawingNotebook>())
        let records = stored.map(\.backupRecord)
        let unknown = records.filter { $0.notebookID == nil }.count
        if unknown > 0 {
            Log.error("백업 — 필사책 ID 를 알 수 없는 필사책 정보는 담지 못한다", "레코드 수=\(unknown)")
        }
        return BackupNotebookRecord.latestPerNotebook(records)
    }
}

extension DrawingSchemaV7.DrawingNotebook {
    /// 이 레코드의 원본 그대로 — 예약 필드(`kind` · `scopeData` · `linkData`)와 모르는 `status` 도 바꾸지 않는다. `notebookID` 가 nil 이면 빈 문자열(형식이 아니다).
    var backupRecord: BackupNotebookRecord {
        BackupNotebookRecord(
            id: notebookID ?? "",
            name: name,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            kind: kind,
            scopeData: scopeData,
            linkData: linkData
        )
    }
}

extension DrawingSchemaV4.BibleDrawing {
    /// 이 행의 원본 그대로 — 백업 전용 조회의 **유일한 변환**이다(내보내기 · 불러오기 판정 · 복원 쓰기가 함께 쓴다).
    ///
    /// 바이트 · `drawingVersion` · 시각 · 번역 저장값 · `isPresent` 를 바꾸지 않는다. 번역이 없으면 nil 그대로다(NKRV 로 채우지 않는다).
    /// `titleName` 도 원문 그대로다(영어 행은 `KJV-…`, 다른 필사책 행은 `nb_<토큰>~…` 접두 포함, 열은 nil) — 백업 키의 번역본 · 필사책은
    /// `BackupRowRecord.backupTranslation` · `backupNotebook` 이 접두로 정한다.
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
