//
//  SwiftDataDrawingRepository+BackupRestore.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  「백업 불러오기」 의 장 단위 복원 쓰기 — 저장소에 쓰는 한 트랜잭션 (설계 docs/backup-import-design.md §4-3 · §5-1).
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
        chapter: BibleChapter,
        generation: DrawingStoreGeneration
    ) async throws -> BackupChapterRestoreOutcome {
        try await actor.restoreBackupChapter(command, chapter: chapter, generation: generation)
    }
}

// MARK: - actor 안의 트랜잭션

extension SwiftDatabaseActor {
    /// 지금 저장소 세대 — 불러오기가 적용을 시작할 때 한 번 읽어 장마다의 복원에 넘긴다(그 뒤 「모든 필사 삭제」 를 잡는다).
    /// - Returns: 지금 세대. 부작용 없음.
    func backupStoreGeneration() -> DrawingStoreGeneration {
        DrawingStoreGeneration(raw: drawingStoreGeneration)
    }

    /// 백업 항목으로 장 하나를 복원한다 — **한 트랜잭션**.
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
    /// | `drawingVersion` · `translation` | 항목 값 그대로(nil 이면 nil — 모델 기본값 1 · NKRV 로 두지 않는다) |
    /// | `creationDate` · `updateDate` | 항목의 `createdAt` · `updatedAt` 그대로 — `BibleDrawing.init` 이 채운 now 를 넣은 뒤 덮는다 |
    /// | `isPresent` | `insertCurrent` 만 true |
    /// | `rowUUID` · business `id` | 새 UUID · `BibleDrawing.init` 규칙(불러온 시각 기준) |
    /// - Parameters:
    ///   - command: 그 장의 항목 · blob 바이트.
    ///   - chapter: 쓸 장.
    ///   - generation: 적용을 시작할 때의 세대.
    /// - Returns: 실제 결정과 적용한 대표 고정. 넣을 것도 고정할 것도 없으면 저장하지 않는다.
    func restoreBackupChapter(
        _ command: BackupChapterRestoreCommand,
        chapter: BibleChapter,
        generation: DrawingStoreGeneration
    ) throws -> BackupChapterRestoreOutcome {
        guard generation.raw == drawingStoreGeneration else {
            Log.error("불러오기 거절 — 적용을 시작한 뒤 필사 데이터가 전부 지워졌다", "명령 세대=\(generation.raw)", "지금 세대=\(drawingStoreGeneration)")
            throw DrawingRepositoryError.staleStoreGeneration
        }
        do {
            let rows = try backupRestoreRows(chapter: chapter)
            let plan = BackupImportPlanner.plan(
                items: command.items,
                unsupported: command.unsupported,
                current: rows.compactMap(\.backupRecord),
                chapter: chapter
            )
            // 쓰기 전에 모두 확인한다 — 하나라도 어긋나면 아무것도 바꾸지 않고 던진다.
            let prepared = try plan.insertions.map { try BackupRestoreRow($0, blobs: command.blobs) }
            let pinned = plan.pins.compactMap { pin in Self.pinTarget(pin, in: rows).map { (pin: pin, row: $0) } }
            if pinned.count < plan.pins.count {
                Log.error("불러오기 — 고정할 대표 행을 찾지 못해 건너뛴다", "\(chapter.title.rawValue).\(chapter.chapter)")
            }
            let outcome = BackupChapterRestoreOutcome(chapter: chapter, decisions: plan.decisions, pins: pinned.map(\.pin))
            guard !prepared.isEmpty || !pinned.isEmpty else { return outcome }

            for row in prepared {
                modelContext.insert(row.makeModel(chapter: chapter))
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

    /// 그 장의 모든 행(대표 · 보관 · 비운 행) — `backupRows(chapter:)` 와 같은 조건.
    private func backupRestoreRows(chapter: BibleChapter) throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
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

/// 넣을 행 하나 — 쓰기 전에 바이트 · 번역값을 모두 확인해 둔다.
private struct BackupRestoreRow {
    let insertion: BackupRowInsertion
    let lineData: Data?
    let layoutMetadataData: Data?
    let translation: Translation?

    /// - Throws: blob 바이트가 없거나 이름과 다르면 `blobUnavailable`, 번역본을 모르면 `unknownTranslation`.
    init(_ insertion: BackupRowInsertion, blobs: [String: Data]) throws {
        self.insertion = insertion
        self.lineData = try insertion.inkBlob.map { try Self.bytes(named: $0, in: blobs) }
        self.layoutMetadataData = try insertion.metadataBlob.map { try Self.bytes(named: $0, in: blobs) }
        if let raw = insertion.translation {
            guard let known = Translation(rawValue: raw) else { throw BackupChapterRestoreError.unknownTranslation }
            self.translation = known
        } else {
            self.translation = nil
        }
    }

    /// blob 바이트 — 이름(SHA-256)과 같은 바이트만 받는다.
    private static func bytes(named name: String, in blobs: [String: Data]) throws -> Data {
        guard let bytes = blobs[name], BackupFormat.sha256Hex(bytes) == name else {
            throw BackupChapterRestoreError.blobUnavailable(name: name)
        }
        return bytes
    }

    /// 모델을 만든다 — 값은 항목 원본 그대로, `rowUUID` 는 새로 발급한다.
    func makeModel(chapter: BibleChapter) -> BibleDrawing {
        let row = BibleDrawing(
            bibleTitle: chapter,
            verse: insertion.verse,
            lineData: lineData,
            updateDate: insertion.updateDate,
            layoutMetadataData: layoutMetadataData,
            rowUUID: UUID().uuidString
        )
        // init 이 now 로 채운 만든 시각과 모델 기본값(좌표 형식 1 · NKRV · isPresent false)을 항목 원본으로 덮는다.
        row.creationDate = insertion.creationDate
        row.drawingVersion = insertion.drawingVersion
        row.translation = translation
        row.isPresent = insertion.isPresent
        return row
    }
}
