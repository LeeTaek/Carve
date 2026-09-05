//
//  SwiftDataDrawingRepository.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

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
