//
//  SwiftDataDrawingRepository+Import.swift
//  Domain
//
//  「확인이 필요한 필기」 의 가져오기 — 저장소에 쓰는 한 트랜잭션 (정책 §12-6 ④, 2026-09-29).
//

import CarveToolkit
import Foundation
import SwiftData

extension SwiftDatabaseActor {
    /// 가져온 필기를 그 절의 **새 대표 행**으로 넣고, 그 절의 다른 행은 대표에서 내린다 — **한 트랜잭션**.
    ///
    /// | 행 | 결과 |
    /// |---|---|
    /// | 새 행 (`command.rowID`) | 가져온 `lineData` · 좌표 정보, `drawingVersion = 3`, **`isPresent = true`**, `updateDate = now` |
    /// | 그 절의 다른 행 | 내용 · `updateDate` 그대로, **`isPresent = false`** — 「이전 필사 내용 보기」 에 남아 다시 고를 수 있다 |
    ///
    /// **지금 필기를 지우지도 덮지도 않는다.** 제자리에서 덮으면(보관 사본 + 교체) 가져오기를 모르고 열려 있던 화면이 그 행에 이어 쓸 때 가져온
    /// 필기가 지워진다. 새 행으로 넣으면 그 획은 옛 행(이전 필사 기록)에 남고 가져온 필기는 대표로 남는다.
    ///
    /// **견준 내용 그대로일 때만 쓴다** — 쓰기 전에 같은 actor 구간에서 그 절의 대표 내용을 다시 읽어 `expectedCurrentFingerprint` 와 견준다.
    /// 다르면 아무것도 쓰지 않고 `currentChanged`, 이미 가져올 내용이면 `alreadyApplied` 다. **세대가 다르면**(견준 뒤 전체 삭제) 던진다.
    /// 같은 명령을 다시 보내도(저장 뒤 결과를 잃은 재시도) 행이 늘지 않는다 — 새 행이 이미 그 내용이면 `alreadyApplied` 다.
    public func importVerseDrawing(
        _ command: VerseDrawingImportCommand,
        chapter: BibleChapter,
        generation: DrawingStoreGeneration,
        now: Date
    ) throws -> VerseDrawingImportOutcome {
        guard generation.raw == drawingStoreGeneration else {
            Log.error("가져오기 거절 — 견준 뒤 필사 데이터가 전부 지워졌다", "명령 세대=\(generation.raw)", "지금 세대=\(drawingStoreGeneration)")
            throw DrawingRepositoryError.staleStoreGeneration
        }
        do {
            // 쓰기 전에 모두 확인한다 — iOS 17 SwiftData 의 rollback 은 외부 저장 Data 를 가진 기존 모델의 메모리 값을 복원하지 못할 수 있다.
            let blob = try importBlob(command)
            let rows = try verseRows(chapter: chapter, verse: command.verse)
            let current = rows.map { importSnapshot($0, verse: command.verse) }.representative()
            let incoming = command.lineData.map {
                VerseContentFingerprint.make(lineData: $0, drawingVersion: 3, layoutMetadataBlob: blob)
            }
            if current?.contentFingerprint == incoming { return .alreadyApplied }
            guard current?.contentFingerprint == command.expectedCurrentFingerprint else { return .currentChanged }

            let previousKept = DrawingContentRule.hasStrokes(current?.lineData)
            for row in rows where row.rowKey != command.rowID.raw {
                row.isPresent = false
            }
            let target: BibleDrawing
            if let existing = rows.first(where: { $0.rowKey == command.rowID.raw }) {
                target = existing
            } else {
                target = BibleDrawing(bibleTitle: chapter, verse: command.verse, lineData: nil, updateDate: now, rowUUID: command.rowID.raw)
                modelContext.insert(target)
            }
            target.lineData = command.lineData
            target.layoutMetadataData = blob
            target.drawingVersion = 3
            target.isPresent = true
            target.updateDate = now
            try modelContext.save()
            return .imported(previousKept: previousKept)
        } catch let error as DrawingRepositoryError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw DrawingRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    /// 가져올 필기의 좌표 정보 blob. 필기가 있는데 좌표 정보가 없거나 인코딩하지 못하면 던진다 — 어디에 놓을지 모르는 필기를 넣지 않는다.
    private func importBlob(_ command: VerseDrawingImportCommand) throws -> Data? {
        guard command.lineData != nil else { return nil }
        guard let metadata = command.metadata else { throw DrawingRepositoryError.metadataEncodingFailed(verse: command.verse) }
        do {
            return try metadata.encodedBlob()
        } catch {
            throw DrawingRepositoryError.metadataEncodingFailed(verse: command.verse)
        }
    }

    /// 그 절의 모든 행(대표 · 보관 · 빈 행).
    private func verseRows(chapter: BibleChapter, verse: Int) throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber && $0.verse == verse
        }
        return try modelContext.fetch(FetchDescriptor(predicate: predicate))
    }

    /// 조회(`loadDrawingSnapshots`)와 같은 모양의 스냅샷 — 목록이 견준 지문과 **같은 규칙**으로 지금 내용을 다시 본다.
    private func importSnapshot(_ row: BibleDrawing, verse: Int) -> VerseDrawingSnapshot {
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
