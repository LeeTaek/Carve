//
//  BackupRestoreRoundTripTesting.swift
//  DomainTest
//
//  불러오기 왕복 — 형식 타입으로 만든 파일과 내보내기가 만든 파일을 빈 저장소에 불러와 원본 그대로인지 본다 (설계 §4-3 「넣는 행」 · §8-2).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 불러온 행의 바이트 · 좌표 형식 · 만든 시각 · 고친 시각 · 번역 저장값이 원본과 달라지는 것(승격 · now 로 덮기 · NKRV 로 채우기)
/// - 백업의 행 식별자를 그대로 써 두 기기가 같은 `rowUUID` 행을 갖는 것
/// - 「비운 현재 + 잉크 보관」 을 불러오면 지운 필기가 대표로 되살아나는 것
@Suite("불러오기 — 왕복")
struct BackupRestoreRoundTripTesting {
    private typealias Sample = BackupRestoreSample

    /// 여러 경우를 한 장에 모은 백업 — v3 · 「비운 현재 + 잉크 보관」 · v2 · nil 좌표 형식과 번역 없음 · 초안 · v1 · 외부 저장으로 빠질 큰 잉크.
    private var mixedEntries: [BackupRestoreEntry] {
        [
            BackupRestoreEntry(verse: 1, sourceKey: "ROW-V3-1", ink: Sample.ink("v3-1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)),
            BackupRestoreEntry(verse: 2, sourceKey: "ROW-CLEARED-2", ink: nil, isCurrent: true, createdAt: Sample.sep(3), updatedAt: Sample.sep(30)),
            BackupRestoreEntry(
                verse: 2, sourceKey: "ROW-ARCHIVED-2", ink: Sample.ink("erased-2"), isCurrent: false, createdAt: Sample.sep(30), updatedAt: Sample.sep(25)
            ),
            BackupRestoreEntry(
                verse: 3, sourceKey: "1-01Genesis.txt.1.3.1773450123", ink: Sample.ink("v2-3"), metadata: nil, drawingVersion: 2,
                isCurrent: true, createdAt: Sample.sep(5), updatedAt: Sample.sep(5)
            ),
            BackupRestoreEntry(
                verse: 4, sourceKey: "1-01Genesis.txt.1.4.1700000000", ink: Sample.ink("legacy-4"), metadata: nil, drawingVersion: nil,
                isCurrent: true, createdAt: nil, updatedAt: nil, translation: nil
            ),
            BackupRestoreEntry(
                kind: .draft, verse: 5, sourceKey: "local|SESSION-1|NKRV|1-01Genesis.txt|1|5|1", ink: Sample.ink("draft-5"),
                isCurrent: true, createdAt: nil, updatedAt: Sample.sep(28)
            ),
            BackupRestoreEntry(
                verse: 6, sourceKey: "ROW-V1-6", ink: Sample.ink("v1-6"), metadata: nil, drawingVersion: 1,
                isCurrent: true, createdAt: Sample.sep(6), updatedAt: Sample.sep(7)
            ),
            BackupRestoreEntry(verse: 7, sourceKey: "ROW-LARGE-7", ink: Sample.largeInk, isCurrent: true, createdAt: Sample.sep(8), updatedAt: Sample.sep(9))
        ]
    }

    @Test("빈 저장소에 불러오면 바이트 · 좌표 형식 · 시각 · 번역 저장값이 원본 그대로이고, rowUUID 는 새로 받고, 대표가 규칙대로다")
    func emptyStoreRoundTripKeepsOriginals() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entries = mixedEntries
        let file = try harness.writeBackup(entries)
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 미리보기와 실제가 같다 — 현재 7(비운 현재 포함) · 보관 1.
        #expect(inspection.targetScope == Sample.accountA)
        #expect(inspection.preview.new == 7)
        #expect(inspection.preview.archived == 1)
        #expect(inspection.preview.chapters == [Sample.genesis1])
        #expect(report == .completed(BackupImportTally(new: 7, archived: 1)))

        // Then: 항목마다 원본 그대로인 행이 하나씩 있다.
        let rows = try await harness.rows()
        #expect(rows.count == entries.count)
        for entry in entries {
            let row = try #require(rows.first { $0.verse == entry.verse && $0.lineData == entry.ink }, "\(entry.sourceKey)")
            #expect(row.matchesOriginal(entry), "\(entry.sourceKey)")
            #expect(row.isPresent == entry.isCurrent, "insertCurrent 만 present — \(entry.sourceKey)")
            // 행 식별자는 새로 받는다 — 백업의 행 키를 쓰지 않는다. business id 는 init 규칙(불러온 시각)이다.
            let rowUUID = try #require(row.rowUUID)
            #expect(UUID(uuidString: rowUUID) != nil)
            #expect(rowUUID != entry.sourceKey)
            #expect(row.businessID?.hasPrefix("\(BibleTitle.genesis.rawValue).1.\(entry.verse).") == true)
        }
        #expect(Set(rows.compactMap(\.rowUUID)).count == rows.count)

        // Then: 대표 — 2절은 비운 행, 나머지는 백업의 현재 필사.
        for entry in entries where entry.isCurrent {
            let representative = try #require(try await harness.representative(verse: entry.verse))
            #expect(representative.lineData == entry.ink, "\(entry.sourceKey)")
            #expect(representative.updateDate == entry.updatedAt, "\(entry.sourceKey)")
        }
        #expect(harness.changes.posted == [LocalDrawingChange(chapter: Sample.genesis1, date: Sample.now)])
    }

    @Test("「비운 현재 + 잉크 보관」 을 빈 저장소에 불러오면 비운 행이 대표로 남고, 지운 필기는 이전 필사 기록에만 있다")
    func clearedCurrentStaysRepresentative() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 백업 — (a) 9/30 에 지운 비운 현재 행, (b) 9/25 의 잉크 있는 보관 행. 메타데이터 blob 은 하나를 함께 가리킨다.
        let cleared = BackupRestoreEntry(verse: 2, sourceKey: "ROW-A", ink: nil, isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(30))
        let erased = BackupRestoreEntry(
            verse: 2, sourceKey: "ROW-B", ink: Sample.ink("erased"), isCurrent: false, createdAt: Sample.sep(30), updatedAt: Sample.sep(25)
        )
        let file = try harness.writeBackup([cleared, erased])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let report = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { _ in }

        // Then: (a) 는 비운 현재 행(present), (b) 는 보관.
        #expect(report == .completed(BackupImportTally(new: 1, archived: 1)))
        let rows = try await harness.rows()
        #expect(rows.count == 2)
        let clearedRow = try #require(rows.first { $0.lineData == nil })
        #expect(clearedRow.isPresent == true)
        #expect(clearedRow.layoutMetadataData == Sample.metadata)
        #expect(rows.first { $0.lineData == Sample.ink("erased") }?.isPresent == false)

        // Then: 화면(장 조회의 대표)은 비운 행 — 절은 비어 보인다. 지운 필기는 「이전 필사 내용 보기」 에만 있다.
        let load = try await SwiftDataDrawingRepository(actor: harness.database).load(chapter: Sample.genesis1)
        let representative = try #require(load.snapshots.representativesByVerse()[2])
        #expect(representative.lineData == nil)
        #expect(load.snapshots.contains { $0.lineData == Sample.ink("erased") && !$0.isPresent })
    }

    @Test("내보내기가 만든 파일을 빈 저장소에 불러오면 행마다 원본 그대로이고 절마다 대표가 같다")
    func exportThenImportRoundTrip() async throws {
        // Given: 내보낼 저장소 — v3 대표와 그 보관 · 「비운 현재 + 잉크 보관」 · 1.3.0 v2(행 키가 business id) · 번역 없음 · 좌표 형식 nil.
        let source = try BackupExportHarness()
        defer { source.remove() }
        let seeds = [
            BackupExportRowSeed(
                verse: 1, rowUUID: "SRC-1", creationDate: Sample.sep(1), updateDate: Sample.sep(10),
                lineData: Sample.ink("current-1"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 1, rowUUID: "SRC-1-OLD", isPresent: false, creationDate: Sample.sep(1), updateDate: Sample.sep(4),
                lineData: Sample.ink("old-1"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "SRC-2-CLEARED", creationDate: Sample.sep(2), updateDate: Sample.sep(30),
                lineData: nil, layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "SRC-2-ERASED", isPresent: false, creationDate: Sample.sep(30), updateDate: Sample.sep(25),
                lineData: Sample.ink("erased-2"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 3, rowUUID: nil, businessID: "1-01Genesis.txt.1.3.1773450123", isPresent: false,
                creationDate: Sample.sep(3), updateDate: Sample.sep(3), drawingVersion: 2, lineData: Sample.ink("v2-3"), layoutMetadataData: nil
            ),
            BackupExportRowSeed(
                verse: 4, rowUUID: "SRC-4", translation: nil, isPresent: nil, creationDate: nil, updateDate: nil,
                drawingVersion: nil, lineData: Sample.ink("legacy-4"), layoutMetadataData: nil
            )
        ]
        try source.seed(seeds)
        let exported = try await source.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: Sample.password) { _ in }
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let report = try await importer.apply(try await importer.inspect(fileURL: exported.fileURL, password: Sample.password)) { _ in }

        // Then: 행마다 바이트 · 좌표 형식 · 시각 · 번역 저장값이 같다(행 식별자는 새로).
        #expect(report.tally.insertCount == seeds.count)
        let imported = try await harness.rows()
        #expect(imported.count == seeds.count)
        for seed in seeds {
            let original = seed.record
            let match = imported.first { row in
                row.verse == original.verse && row.lineData == original.lineData && row.layoutMetadataData == original.layoutMetadataData
                    && row.drawingVersion == original.drawingVersion && row.creationDate == original.creationDate
                    && row.updateDate == original.updateDate && row.translation == original.translation
            }
            #expect(match != nil, "\(original.rowKey)")
            #expect(match?.rowKey != original.rowKey)
        }
        // Then: 절마다 대표의 내용 · 시각이 내보낸 저장소와 같다(2절은 비운 행).
        let exportedRows = try await source.database.backupRows(chapter: Sample.genesis1).rows
        for verse in 1...4 {
            let before = DrawingRepresentativeRule.pick(exportedRows.filter { $0.verse == verse })
            let after = try await harness.representative(verse: verse)
            #expect(after?.contentFingerprint == before?.contentFingerprint, "\(verse)절")
            #expect(after?.updateDate == before?.updateDate, "\(verse)절")
        }
        #expect(try await harness.representative(verse: 2)?.lineData == nil)
    }
}
