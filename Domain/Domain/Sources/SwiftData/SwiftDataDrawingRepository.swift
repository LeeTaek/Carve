//
//  SwiftDataDrawingRepository.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation
import SwiftData

import Dependencies

/// `DrawingRepository` 의 SwiftData 구현 (설계 §8-6 · §8-7).
///
/// 모든 읽기·쓰기는 `SwiftDatabaseActor` 안에서 일어난다. 트랜잭션 경계도 actor 메서드 하나다 —
/// 변경을 모아 **마지막에 `save()` 1회**, 실패하면 `rollback()` (§8-6 "구현 지점").
public struct SwiftDataDrawingRepository: DrawingRepository {
    private let actor: SwiftDatabaseActor

    /// - Parameter actor: 사용할 actor. 생략하면 현재 의존성의 actor.
    public init(actor: SwiftDatabaseActor? = nil) {
        if let actor {
            self.actor = actor
        } else {
            @Dependency(\.createSwiftDataActor) var injected
            self.actor = injected
        }
    }

    public func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot] {
        try await actor.loadDrawingSnapshots(chapter: chapter)
    }

    public func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws {
        try await actor.applyDrawingMutations(mutations, chapter: chapter, now: Date())
    }

    public func archiveAndReset(
        _ command: VerseDrawingArchiveCommand,
        chapter: BibleChapter
    ) async throws -> VerseDrawingArchiveOutcome {
        try await actor.archiveAndResetVerseDrawing(command, chapter: chapter, now: Date())
    }
}

// MARK: - actor 안의 트랜잭션

extension SwiftDatabaseActor {
    /// 장의 모든 `BibleDrawing` 행을 스냅샷으로 읽는다.
    ///
    /// 행 키는 `rowUUID` 가 있으면 그것, 없으면(legacy) business `id` 다 (§8-7). 절 → 행 키 순으로 정렬해
    /// 호출 순서와 무관하게 같은 결과를 낸다.
    /// - Parameter chapter: 대상 장.
    /// - Returns: 스냅샷 배열.
    public func loadDrawingSnapshots(chapter: BibleChapter) throws -> [VerseDrawingSnapshot] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber
        }
        let rows: [BibleDrawing] = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        return rows
            .compactMap { row -> VerseDrawingSnapshot? in
                guard let verse = row.verse else { return nil }
                return VerseDrawingSnapshot(
                    verse: verse,
                    rowID: BibleDrawingRowID(raw: row.rowKey),
                    isPresent: row.isPresent ?? false,
                    updateDate: row.updateDate,
                    lineData: row.lineData,
                    drawingVersion: row.drawingVersion,
                    metadata: DrawingLayoutMetadata.decode(blob: row.layoutMetadataData)
                )
            }
            .sorted { lhs, rhs in
                lhs.verse != rhs.verse ? lhs.verse < rhs.verse : lhs.rowID < rhs.rowID
            }
    }

    /// 저장 명령들을 **한 트랜잭션**으로 적용한다 (P8).
    ///
    /// | 명령 | 하는 일 |
    /// |---|---|
    /// | `create` | **upsert.** 행이 없으면 삽입(`rowUUID` = 선발급 rowID, `drawingVersion = 3`, `isPresent = true`),
    ///   있으면 `replace` 처럼 갱신. 같은 rowID 의 `create` 가 두 번 와도 행은 하나다 (§8-7 "해당 rowID 를 upsert") |
    /// | `replace` | `lineData` · `layoutMetadataData` 교체, `drawingVersion = 3` 으로 승격 (§10-2 정책 5), `updateDate` 갱신.
    ///   **행이 없으면 실패** — 주소지정 버그를 조용히 새 행으로 바꾸지 않는다 |
    /// | `clear` | **행 유지**, `lineData = nil`, `updateDate` 갱신 (§8-7). 행이 없으면(그렸다가 저장 전에 지운 절)
    ///   **빈 행을 만든다** — 앞선 `create` 가 저장됐든 아니든 결과가 같아야 하기 때문 |
    ///
    /// 하나라도 실패하면 `rollback()` 으로 이 트랜잭션의 변경을 전부 버리고 던진다.
    /// - Parameters:
    ///   - mutations: 저장 명령.
    ///   - chapter: 대상 장.
    ///   - now: `updateDate` 에 기록할 시각.
    public func applyDrawingMutations(
        _ mutations: [VerseDrawingMutation],
        chapter: BibleChapter,
        now: Date
    ) throws {
        do {
            for mutation in mutations {
                switch mutation {
                case .create(let verse, let rowID, let data, let metadata):
                    let blob = try encode(metadata, verse: verse)
                    if let existing = try drawingRow(rowID: rowID, chapter: chapter) {
                        existing.lineData = data
                        existing.layoutMetadataData = blob
                        existing.drawingVersion = 3
                        existing.updateDate = now
                    } else {
                        let row = BibleDrawing(
                            bibleTitle: chapter, verse: verse, lineData: data, updateDate: now,
                            layoutMetadataData: blob, rowUUID: rowID.raw
                        )
                        row.drawingVersion = 3
                        row.isPresent = true
                        modelContext.insert(row)
                    }

                case .replace(let verse, let rowID, let data, let metadata):
                    let row = try requireDrawingRow(rowID: rowID, chapter: chapter)
                    row.lineData = data
                    row.layoutMetadataData = try encode(metadata, verse: verse)
                    row.drawingVersion = 3
                    row.updateDate = now

                case .clear(let verse, let rowID):
                    if let row = try drawingRow(rowID: rowID, chapter: chapter) {
                        row.lineData = nil
                        row.updateDate = now
                    } else {
                        let row = BibleDrawing(bibleTitle: chapter, verse: verse, lineData: nil, updateDate: now, rowUUID: rowID.raw)
                        row.drawingVersion = 3
                        row.isPresent = true
                        modelContext.insert(row)
                    }
                }
            }
            try modelContext.save()
        } catch let error as DrawingRepositoryError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw DrawingRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    /// 절의 현재 필사를 보관 행으로 남기고 활성 행을 비운다 — **한 트랜잭션** (UI-2 "지우기", §8-6 과 같은 경계).
    ///
    /// 삭제하지 않는다. 두 행 모두 남으며, 달라지는 것은 "어느 행이 대표인가" 와 "활성 행에 획이 있는가" 뿐이다.
    ///
    /// | 행 | 결과 |
    /// |---|---|
    /// | 보관 행 (`archiveRowID`) | 활성 행의 `lineData` · `layoutMetadataData` · `drawingVersion` 복제, **`isPresent = false`**, `updateDate` 는 원래 필사 시각 유지 |
    /// | 활성 행 (`activeRowID`) | 행 유지, `lineData = nil`, **`isPresent = true`**(대표 유지), `updateDate = now` |
    ///
    /// **보관 행이 다시 대표로 뽑히지 않는 이유가 여기 있다.** `VerseDrawingMutation.clear` 는 기존 행의 `isPresent` 를
    /// 바꾸지 않으므로 대표 규칙(`DrawingRepresentativeRule`: `isPresent` 우선 → `updateDate` 최신)을 이 작업이 직접
    /// 보장해야 한다. 보관 행의 `updateDate` 를 원래 값으로 두는 것도 같은 이유다 — `isPresent` 가 하나도 없는
    /// 예외 상황(CloudKit 충돌)에서도 `now` 인 빈 활성 행이 최신이라 대표를 지킨다. 기록 목록의 "필사 날짜" 도 그 값이 맞다.
    ///
    /// **재시도 안전.** `archiveRowID` 는 호출부가 작업당 한 번 발급해 재시도에도 같은 값을 넘긴다. 여기서는 그 rowID 를
    /// upsert 로 다루므로 재시도가 보관 행을 늘리지 않는다. 게다가 재시도 시점에는 이미 활성 행이 비어 있어
    /// `alreadyEmpty` 로 조기 반환된다.
    ///
    /// - Important: 호출 전에 미저장분이 전부 저장돼 있어야 한다 (§8-5 flush). 이 메서드가 보관하는 것은 **DB 의 활성 행**이다.
    /// - Parameters:
    ///   - command: 대상 절 · 활성 행 · 보관 행 식별자.
    ///   - chapter: 대상 장.
    ///   - now: 활성 행의 `updateDate` 에 기록할 시각.
    /// - Returns: 실제로 보관했으면 `.archived`, 비어 있어 아무것도 쓰지 않았으면 `.alreadyEmpty`.
    public func archiveAndResetVerseDrawing(
        _ command: VerseDrawingArchiveCommand,
        chapter: BibleChapter,
        now: Date
    ) throws -> VerseDrawingArchiveOutcome {
        do {
            // 획이 하나도 없으면 보관본을 만들지 않는다. 지우개로 전부 지운 절은 `lineData` 가 남아 있어도 stroke 가 0개다.
            guard let active = try drawingRow(rowID: command.activeRowID, chapter: chapter),
                  active.lineData?.containsPKStroke == true else {
                return .alreadyEmpty
            }

            let archived: BibleDrawing
            if let existing = try drawingRow(rowID: command.archiveRowID, chapter: chapter) {
                archived = existing
            } else {
                let row = BibleDrawing(
                    bibleTitle: chapter, verse: command.verse, lineData: nil, updateDate: now,
                    rowUUID: command.archiveRowID.raw
                )
                modelContext.insert(row)
                archived = row
            }
            archived.verse = command.verse
            archived.lineData = active.lineData
            archived.layoutMetadataData = active.layoutMetadataData
            archived.drawingVersion = active.drawingVersion
            archived.isPresent = false
            archived.updateDate = active.updateDate ?? now

            active.lineData = nil
            active.isPresent = true
            active.updateDate = now

            try modelContext.save()
            return .archived
        } catch let error as DrawingRepositoryError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw DrawingRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    // MARK: 내부

    private func drawingRow(rowID: BibleDrawingRowID, chapter: BibleChapter) throws -> BibleDrawing? {
        let raw = rowID.raw
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber
                && ($0.rowUUID == raw || $0.id == raw)
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func requireDrawingRow(rowID: BibleDrawingRowID, chapter: BibleChapter) throws -> BibleDrawing {
        guard let row = try drawingRow(rowID: rowID, chapter: chapter) else {
            throw DrawingRepositoryError.rowNotFound(rowID)
        }
        return row
    }

    private func encode(_ metadata: DrawingLayoutMetadata, verse: Int) throws -> Data {
        do {
            return try metadata.encodedBlob()
        } catch {
            throw DrawingRepositoryError.metadataEncodingFailed(verse: verse)
        }
    }
}

// MARK: - 행 키

public extension DrawingSchemaV4.BibleDrawing {
    /// 도메인 행 키 (§8-7). `rowUUID` 가 있으면 그것, 없으면 business `id`.
    ///
    /// `drawing.id` 표현은 문맥에 따라 `String!` 과 `PersistentIdentifier` 로 다르게 해석되므로(§8-7, S0-3)
    /// 새 코드는 이 프로퍼티만 쓴다.
    var rowKey: String {
        if let rowUUID, !rowUUID.isEmpty { return rowUUID }
        let business: String? = id
        return business ?? ""
    }
}

extension DrawingSchemaV4.BibleDrawing: DrawingRepresentativeCandidate {
    public var representativeIsPresent: Bool { isPresent ?? false }
    public var representativeUpdateDate: Date? { updateDate }
    public var representativeRowKey: String { rowKey }
}
