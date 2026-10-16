//
//  SwiftDataDrawingRepository+BackupRestore.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  「백업 불러오기」 의 장 단위 복원 쓰기 — 저장소에 쓰는 한 트랜잭션 (설계 docs/backup-import-design.md §4-3 · §5-1).
//  장은 필사책 안의 장(`NotebookChapter`)이다. 필사책 목록(`DrawingNotebook`)의 복원 쓰기도 여기 actor 확장에 둔다(형식 2).
//

import CarveToolkit
import Foundation
import SwiftData

/// `DrawingBackupRestoring` 의 SwiftData 구현 — 이 실행의 저장소 actor 하나로 쓴다.
///
/// `SwiftDataDrawingRepository` 는 actor 를 `private` 으로 들어 다른 파일의 확장이 쓸 수 없다. 그 파일을 고치지 않으려고
/// 같은 actor 를 받는 구현을 따로 둔다 — 앱은 편집 화면 · 「모든 필사 삭제」 와 **같은** `SwiftDatabaseActor` 로 만든다(그래야 세대가 뜻을 가진다).
public struct SwiftDataDrawingBackupRestorer: DrawingBackupRestoring {
    private let actor: SwiftDatabaseActor

    /// - Parameter actor: 이 실행의 저장소 actor.
    public init(actor: SwiftDatabaseActor) {
        self.actor = actor
    }

    public func restore(
        _ command: BackupChapterRestoreCommand,
        page: NotebookChapter,
        generation: DrawingStoreGeneration
    ) async throws -> BackupChapterRestoreOutcome {
        try await actor.restoreBackupChapter(command, page: page, generation: generation)
    }

    public func restoreNotebooks(_ records: [BackupNotebookRecord], generation: DrawingStoreGeneration) async throws -> BackupNotebookRestoreOutcome {
        try await actor.restoreBackupNotebooks(records, generation: generation)
    }
}

// MARK: - actor 안의 트랜잭션

extension SwiftDatabaseActor {
    /// 지금 저장소 세대 — 불러오기가 적용을 시작할 때 한 번 읽어 장마다의 복원에 넘긴다(그 뒤 「모든 필사 삭제」 를 잡는다).
    /// - Returns: 지금 세대. 부작용 없음.
    func backupStoreGeneration() -> DrawingStoreGeneration {
        DrawingStoreGeneration(raw: drawingStoreGeneration)
    }

    /// 백업 항목으로 필사책 안의 장 하나를 복원한다 — **한 트랜잭션**.
    ///
    /// 1. 세대가 다르면 아무것도 쓰지 않고 `staleStoreGeneration` 을 던진다.
    /// 2. 그 장의 모든 행을 백업 전용 조회와 **같은 변환**(`backupRecord`)으로 다시 읽고 `BackupImportPlanner` 로 다시 판정한다.
    /// 3. 쓰기 전에 넣을 행의 바이트 · 번역값과 고정할 행을 모두 확인한다 — iOS 17 SwiftData 의 rollback 은 외부 저장 Data 를 가진
    ///    기존 모델의 메모리 값을 복원하지 못할 수 있다(`importVerseDrawing` 과 같은 주의).
    /// 4. 넣을 행을 만들고(원본 그대로 · 새 `rowUUID`) 고정할 행의 `isPresent` 만 true 로 바꾼 뒤 `save()` 한 번. 실패하면 `rollback()`.
    ///
    /// | 넣는 행 | 값 |
    /// |---|---|
    /// | `lineData` · `layoutMetadataData` | blob 원본 바이트(비운 행이면 `lineData` nil) |
    /// | `drawingVersion` | 항목 값 그대로(nil 이면 nil — 모델 기본값 1 로 두지 않는다) |
    /// | `translation` | 개역개정 항목은 값 그대로(nil 이면 nil — 모델 기본값 NKRV 로 두지 않는다). KJV · BSB 항목은 nil(`StoredBookKey.translationColumn`) |
    /// | `titleName` | `StoredBookKey.titleName(for: page)` — 기본 필사책은 개역개정 · nil 이 `BibleTitle.rawValue`, 영어는 `KJV-<rawValue>` 등, 다른 필사책은 그 앞에 `nb_<토큰>~` |
    /// | `creationDate` · `updateDate` | 항목의 `createdAt` · `updatedAt` 그대로 — `BibleDrawing.init` 이 채운 now 를 넣은 뒤 덮는다 |
    /// | `isPresent` | `insertCurrent` 만 true |
    /// | `rowUUID` · business `id` | 새 UUID · `BibleDrawing.init(page:…)` 규칙(불러온 시각 기준 · 필사책 접두 포함) |
    /// - Parameters:
    ///   - command: 그 장의 항목 · blob 바이트.
    ///   - page: 쓸 장(필사책 · 번역본 포함).
    ///   - generation: 적용을 시작할 때의 세대.
    /// - Returns: 실제 결정과 적용한 대표 고정. 넣을 것도 고정할 것도 없으면 저장하지 않는다.
    func restoreBackupChapter(
        _ command: BackupChapterRestoreCommand,
        page: NotebookChapter,
        generation: DrawingStoreGeneration
    ) throws -> BackupChapterRestoreOutcome {
        guard generation.raw == drawingStoreGeneration else {
            Log.error("불러오기 거절 — 적용을 시작한 뒤 필사 데이터가 전부 지워졌다", "명령 세대=\(generation.raw)", "지금 세대=\(drawingStoreGeneration)")
            throw DrawingRepositoryError.staleStoreGeneration
        }
        do {
            let rows = try backupRestoreRows(page: page)
            let plan = BackupImportPlanner.plan(
                items: command.items,
                unsupported: command.unsupported,
                current: rows.compactMap(\.backupRecord),
                page: page
            )
            // 쓰기 전에 모두 확인한다 — 하나라도 어긋나면 아무것도 바꾸지 않고 던진다.
            let prepared = try plan.insertions.map { try BackupRestoreRow($0, blobs: command.blobs) }
            let pinned = plan.pins.compactMap { pin in Self.pinTarget(pin, in: rows).map { (pin: pin, row: $0) } }
            if pinned.count < plan.pins.count {
                Log.error("불러오기 — 고정할 대표 행을 찾지 못해 건너뛴다", "\(StoredBookKey.titleName(for: page)).\(page.chapter.chapter)")
            }
            let outcome = BackupChapterRestoreOutcome(page: page, decisions: plan.decisions, pins: pinned.map(\.pin))
            guard !prepared.isEmpty || !pinned.isEmpty else { return outcome }

            for row in prepared {
                modelContext.insert(row.makeModel(page: page))
            }
            for target in pinned {
                target.row.isPresent = true
            }
            try modelContext.save()
            return outcome
        } catch let error as DrawingRepositoryError {
            modelContext.rollback()
            throw error
        } catch let error as BackupChapterRestoreError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw DrawingRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    /// 그 장의 모든 행(대표 · 보관 · 비운 행) — `backupRows(page:)` 와 같은 조건(그 장의 필사책 · 번역본 `titleName`).
    private func backupRestoreRows(page: NotebookChapter) throws -> [BibleDrawing] {
        let titleName = StoredBookKey.titleName(for: page)
        let chapterNumber = page.chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber
        }
        return try modelContext.fetch(FetchDescriptor(predicate: predicate))
    }

    /// 고정할 지금 행 — 그 절에서 행 키가 같은 행. 같은 키가 둘이면(1.3.0 의 같은 초 business id) 대표 규칙이 고르는 쪽이다.
    private static func pinTarget(_ pin: BackupRepresentativePin, in rows: [BibleDrawing]) -> BibleDrawing? {
        DrawingRepresentativeRule.pick(rows.filter { $0.verse == pin.verse && $0.rowKey == pin.rowKey })
    }
}

// MARK: - 필사책 목록

extension SwiftDatabaseActor {
    /// 백업의 필사책 목록을 `DrawingNotebook` 에 복원한다 — **한 트랜잭션**(형식 2).
    ///
    /// 1. 세대가 다르면 아무것도 쓰지 않고 `staleStoreGeneration` 을 던진다.
    /// 2. 백업 목록을 필사책마다 하나로 줄인다(`BackupNotebookRecord.latestPerNotebook` — ID 형식이 아닌 레코드는 건너뛴다).
    /// 3. 필사책마다: 저장소에 그 ID 의 레코드가 없으면 백업 값 그대로 하나 넣는다. 있으면 저장소의 최신 레코드(`isNewer(than:)` — 저장소 읽기와
    ///    같은 규칙)와 견줘 백업이 늦을 때만 그 ID 의 레코드 **전부**를 백업 값으로 바꾼다(이름 바꾸기와 같이 — 중복을 지우지 않는다).
    ///    같거나 이르면 그대로 둔다 — 같은 파일을 다시 불러와도 바뀌지 않는다.
    /// 4. 바꾼 것이 있으면 `save()` 한 번. 실패하면 `rollback()`.
    ///
    /// 레코드는 지우지 않는다. 필드는 예약 필드(`kind` · `scopeData` · `linkData`)와 모르는 `status` 까지 원본 그대로 쓴다.
    /// - Parameters:
    ///   - records: 백업의 필사책 목록.
    ///   - generation: 적용을 시작할 때의 세대.
    /// - Returns: 넣은 · 바꾼 · 그대로 둔 · 건너뛴 수.
    /// - Throws: 세대가 다르면 `staleStoreGeneration`, 조회 · 저장 실패는 `persistenceFailed`.
    func restoreBackupNotebooks(_ records: [BackupNotebookRecord], generation: DrawingStoreGeneration) throws -> BackupNotebookRestoreOutcome {
        guard generation.raw == drawingStoreGeneration else {
            Log.error("불러오기 거절 — 적용을 시작한 뒤 필사 데이터가 전부 지워졌다(필사책 목록)", "명령 세대=\(generation.raw)", "지금 세대=\(drawingStoreGeneration)")
            throw DrawingRepositoryError.staleStoreGeneration
        }
        let incoming = BackupNotebookRecord.latestPerNotebook(records)
        let skipped = records.filter { $0.notebookID == nil }.count
        if skipped > 0 {
            Log.error("불러오기 — 필사책 ID 를 알 수 없는 필사책 정보는 건너뛴다", "레코드 수=\(skipped)")
        }
        guard !incoming.isEmpty else { return BackupNotebookRestoreOutcome(skipped: skipped) }
        do {
            let stored: [DrawingNotebook] = try modelContext.fetch(FetchDescriptor<DrawingNotebook>())
            var storedByID: [String: [DrawingNotebook]] = [:]
            for notebook in stored {
                guard let id = notebook.notebookID else { continue }
                storedByID[id, default: []].append(notebook)
            }
            var inserted = 0
            var updated = 0
            var unchanged = 0
            for record in incoming {
                let existing = storedByID[record.id] ?? []
                guard let first = existing.first else {
                    let notebook = DrawingNotebook()
                    notebook.applyBackupRecord(record)
                    modelContext.insert(notebook)
                    inserted += 1
                    continue
                }
                var latest = first.backupRecord
                for candidate in existing.dropFirst().map(\.backupRecord) where candidate.isNewer(than: latest) {
                    latest = candidate
                }
                guard record.isNewer(than: latest) else {
                    unchanged += 1
                    continue
                }
                for notebook in existing {
                    notebook.applyBackupRecord(record)
                }
                updated += 1
            }
            if inserted > 0 || updated > 0 {
                try modelContext.save()
            }
            return BackupNotebookRestoreOutcome(inserted: inserted, updated: updated, unchanged: unchanged, skipped: skipped)
        } catch {
            modelContext.rollback()
            throw DrawingRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }
}

extension DrawingSchemaV7.DrawingNotebook {
    /// 백업 레코드의 값을 그대로 적는다 — 예약 필드 · 모르는 `status` 도 바꾸지 않는다.
    func applyBackupRecord(_ record: BackupNotebookRecord) {
        notebookID = record.id
        name = record.name
        status = record.status
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        completedAt = record.completedAt
        kind = record.kind
        scopeData = record.scopeData
        linkData = record.linkData
    }
}

/// 넣을 행 하나 — 쓰기 전에 바이트 · 번역값을 모두 확인해 둔다.
private struct BackupRestoreRow {
    let insertion: BackupRowInsertion
    let lineData: Data?
    let layoutMetadataData: Data?
    /// `translation` 열에 쓸 값 — `.NKRV` 나 nil 만(영어 값은 쓰지 않는다 — 이미 나간 2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다).
    let translationColumn: Translation?
    /// `titleName` 에 쓸 값 — 장의 필사책 · 권 · 번역본으로 지은 `StoredBookKey.titleName(for: page)`(항목의 번역본 · 필사책과 같은 것을 확인했다).
    let titleName: String

    /// - Throws: blob 바이트가 없거나 이름과 다르면 `blobUnavailable`, 번역본을 모르거나 장의 번역본과 다르면 `unknownTranslation`,
    ///   항목의 필사책이 장의 필사책과 다르면 `notebookMismatch`.
    init(_ insertion: BackupRowInsertion, blobs: [String: Data]) throws {
        self.insertion = insertion
        self.lineData = try insertion.inkBlob.map { try Self.bytes(named: $0, in: blobs) }
        self.layoutMetadataData = try insertion.metadataBlob.map { try Self.bytes(named: $0, in: blobs) }
        // 번역 nil 은 개역개정 묶음이고 열에는 nil 그대로 쓴다(NKRV 로 채우지 않는다).
        let translation: Translation
        if let raw = insertion.translation {
            guard let known = Translation(rawValue: raw) else { throw BackupChapterRestoreError.unknownTranslation }
            translation = known
            self.translationColumn = StoredBookKey.translationColumn(for: known)
        } else {
            translation = .NKRV
            self.translationColumn = nil
        }
        // 판정기는 장과 같은 번역본 항목만 넣는다 — 어긋나면 다른 번역본 장에 행이 섞이므로 쓰지 않는다.
        guard translation == insertion.page.chapter.translation else { throw BackupChapterRestoreError.unknownTranslation }
        // 판정기는 장과 같은 필사책 항목만 넣는다 — 어긋나면 다른 필사책(특히 기본 필사책) 행에 섞이므로 쓰지 않는다.
        let notebook: NotebookID? = if let token = insertion.notebook { NotebookID(rawValue: token) } else { .default }
        guard notebook == insertion.page.notebook else { throw BackupChapterRestoreError.notebookMismatch }
        self.titleName = insertion.titleName
    }

    /// blob 바이트 — 이름(SHA-256)과 같은 바이트만 받는다.
    private static func bytes(named name: String, in blobs: [String: Data]) throws -> Data {
        guard let bytes = blobs[name], BackupFormat.sha256Hex(bytes) == name else {
            throw BackupChapterRestoreError.blobUnavailable(name: name)
        }
        return bytes
    }

    /// 모델을 만든다 — 값은 항목 원본 그대로, `rowUUID` 는 새로 발급한다. business id 는 장의 필사책 `titleName` 으로 짓는다.
    func makeModel(page: NotebookChapter) -> BibleDrawing {
        let row = BibleDrawing(
            page: page,
            verse: insertion.verse,
            lineData: lineData,
            updateDate: insertion.updateDate,
            layoutMetadataData: layoutMetadataData,
            rowUUID: UUID().uuidString
        )
        // init 이 now 로 채운 만든 시각과 모델 기본값(좌표 형식 1 · NKRV · isPresent false)을 항목 원본으로 덮는다.
        // 권 이름 · 번역 열도 init 규칙에 기대지 않고 확인해 둔 값으로 적는다(영어 행은 `KJV-…` · 열 nil, 다른 필사책은 `nb_<토큰>~` 접두).
        row.titleName = titleName
        row.creationDate = insertion.creationDate
        row.drawingVersion = insertion.drawingVersion
        row.translation = translationColumn
        row.isPresent = insertion.isPresent
        return row
    }
}
