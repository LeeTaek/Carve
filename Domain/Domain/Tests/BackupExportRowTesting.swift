//
//  BackupExportRowTesting.swift
//  DomainTest
//
//  필사 백업 내보내기 — 저장소 행을 원본 그대로 담는다 (설계 docs/backup-import-design.md §3-3 · §5-3).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 행을 표시용 조회(`VerseDrawingSnapshot`)로 읽어 만든 시각 · 번역 저장값 · 행 키 구분 · 메타데이터 원본 바이트를 잃는 것
/// - `drawingVersion` 을 승격 · 강등하거나, 번역이 없는 행을 NKRV 로 채우는 것
/// - 대표가 아닌 행을 현재로 담거나, **비운 대표 행**을 빼서 같은 절의 잉크 보관 행이 대표로 올라가는 것(지운 필기가 되살아난다)
/// - 같은 바이트의 blob 을 두 번 쓰는 것
@Suite("백업 내보내기 — 행")
struct BackupExportRowTesting {

    @Test("v1 · v2 · v3 · nil · 비운 행 · 보관 행을 원본 바이트 · 시각 · 번역값 그대로 담는다 — 메타데이터는 키 순서까지")
    func rowsKeepTheirOriginalFieldsAndBytes() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 1.3.0 행(v1 · 번역 없음 · business id), v2, v3(키 순서가 다른 메타데이터), 좌표 형식 nil, 「지우기」 뒤의 비운 대표 + 잉크 보관 행.
        let seeds = [
            BackupExportRowSeed(
                verse: 1, rowUUID: nil, businessID: "1-01Genesis.txt.1.1.1773450123", translation: nil, isPresent: false,
                drawingVersion: 1, lineData: BackupExportSample.ink("v1"), layoutMetadataData: nil
            ),
            BackupExportRowSeed(verse: 2, rowUUID: "ROW-V2", drawingVersion: 2, lineData: BackupExportSample.ink("v2"), layoutMetadataData: nil),
            BackupExportRowSeed(
                verse: 3, rowUUID: "ROW-V3", drawingVersion: 3, lineData: BackupExportSample.ink("v3"), layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 4, rowUUID: "ROW-NIL", creationDate: nil, drawingVersion: nil, lineData: BackupExportSample.ink("nil"), layoutMetadataData: nil
            ),
            BackupExportRowSeed(
                verse: 5, rowUUID: "ROW-CLEARED", updateDate: BackupExportSample.clearedAt, drawingVersion: 3,
                lineData: nil, layoutMetadataData: BackupExportSample.otherMetadata
            ),
            BackupExportRowSeed(
                verse: 5, rowUUID: "ROW-ARCHIVED", isPresent: false, updateDate: BackupExportSample.archivedAt, drawingVersion: 3,
                lineData: BackupExportSample.ink("archived"), layoutMetadataData: BackupExportSample.otherMetadata
            )
        ]
        try harness.seed(seeds)

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then: 행마다 원본 그대로
        #expect(payload.items.count == seeds.count)
        for seed in seeds {
            let record = seed.record
            let item = try #require(payload.row(seed.rowKey), "행 \(seed.rowKey) 이 없다")
            #expect(item.id == BackupItemID.make(kind: .row, sourceKey: seed.rowKey, fingerprint: record.contentFingerprint))
            #expect(item.parents.isEmpty)
            #expect(item.verse == BackupVerseKey(translation: seed.translation?.rawValue, book: "GEN", chapter: 1, verse: seed.verse ?? 0))
            #expect(item.drawingVersion == seed.drawingVersion)
            #expect(item.createdAt == seed.creationDate)
            #expect(item.updatedAt == seed.updateDate)
            #expect(item.fingerprint == record.contentFingerprint)
            #expect(item.source == BackupItemSource(titleName: BibleTitle.genesis.rawValue, rowKey: seed.rowKey))
            #expect(payload.bytes(item.inkBlob) == seed.lineData)
            #expect(payload.bytes(item.metadataBlob) == seed.layoutMetadataData)
        }
        // 번역이 없는 행은 null 그대로(NKRV 로 채우지 않는다), 1.3.0 행의 행 키는 business id 다.
        #expect(payload.row("1-01Genesis.txt.1.1.1773450123")?.verse.translation == nil)
        // 메타데이터는 다시 인코딩하지 않는다 — 키 순서 · 공백까지 원본 바이트다.
        #expect(payload.bytes(payload.row("ROW-V3")?.metadataBlob) == BackupExportSample.metadata)
        // 비운 행은 잉크 · 지문 없이 메타데이터만 든다.
        let cleared = try #require(payload.row("ROW-CLEARED"))
        #expect(cleared.inkBlob == nil && cleared.fingerprint == nil && cleared.metadataBlob != nil)

        // manifest — 이 실행의 값과 수.
        #expect(payload.manifest.formatVersion == BackupFormat.formatVersion)
        #expect(payload.manifest.appVersion == "2.1.0")
        #expect(payload.manifest.createdAt == BackupExportSample.now)
        #expect(payload.manifest.scope == BackupScope(rows: true, drafts: true))
        #expect(payload.manifest.counts == BackupCounts(rows: 6, drafts: 0, blobs: 7))
        #expect(result.counts == payload.manifest.counts)
        #expect(result.backupID == payload.manifest.backupID)
        #expect(UUID(uuidString: result.backupID) != nil)
    }

    @Test("그 절의 대표 행만 현재다 — isPresent 행 중 최신, isPresent 행이 없으면 전체에서 최신")
    func onlyTheRepresentativeRowIsCurrent() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 1절 — 대표(isPresent · 최신), 옛 대표(isPresent · 이전), 더 늦은 보관 행. 2절 — isPresent 행이 없다.
        try harness.seed([
            BackupExportRowSeed(
                verse: 1, rowUUID: "V1-PRESENT-NEW", isPresent: true, updateDate: Date(timeIntervalSinceReferenceDate: 2_000),
                lineData: BackupExportSample.ink("1-new"), layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 1, rowUUID: "V1-PRESENT-OLD", isPresent: true, updateDate: Date(timeIntervalSinceReferenceDate: 1_000),
                lineData: BackupExportSample.ink("1-old"), layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 1, rowUUID: "V1-ARCHIVED-NEWEST", isPresent: false, updateDate: Date(timeIntervalSinceReferenceDate: 3_000),
                lineData: BackupExportSample.ink("1-archived"), layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "V2-OLD", isPresent: nil, updateDate: Date(timeIntervalSinceReferenceDate: 1_000),
                lineData: BackupExportSample.ink("2-old"), layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "V2-NEW", isPresent: false, updateDate: Date(timeIntervalSinceReferenceDate: 2_000),
                lineData: BackupExportSample.ink("2-new"), layoutMetadataData: BackupExportSample.metadata
            )
        ])

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then
        let current = Set(payload.items.filter(\.isCurrent).compactMap(\.source.rowKey))
        #expect(current == ["V1-PRESENT-NEW", "V2-NEW"])
        // isPresent 원본은 담지 않는다 — 현재 표시는 대표 규칙의 결과다.
        #expect(payload.items.count == 5)
    }

    /// 「지우기」(`archiveAndResetVerseDrawing`) 뒤의 절 — 비운 대표를 빼거나 현재가 아니게 담으면 불러온 기기에서 잉크 보관 행이 대표로 올라가
    /// 지운 필기가 되살아난다(설계 §5-1 「비운 대표 행」).
    @Test("비운 대표 + 잉크 보관 행이면 비운 행이 현재다 — 둘이 같은 메타데이터 blob 하나를 함께 가리킨다")
    func clearedRepresentativeStaysCurrent() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 비운 대표(isPresent · 9/30) + 지운 잉크를 든 보관 행(9/25) — 같은 메타데이터 바이트.
        try harness.seed([
            BackupExportRowSeed(
                verse: 2, rowUUID: "CLEARED", isPresent: true, updateDate: BackupExportSample.clearedAt,
                lineData: nil, layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "ARCHIVED", isPresent: false, updateDate: BackupExportSample.archivedAt,
                lineData: BackupExportSample.ink("지운 필기"), layoutMetadataData: BackupExportSample.metadata
            )
        ])

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then
        let cleared = try #require(payload.row("CLEARED"))
        let archived = try #require(payload.row("ARCHIVED"))
        #expect(cleared.isCurrent)
        #expect(!archived.isCurrent)
        #expect(cleared.inkBlob == nil && cleared.fingerprint == nil)
        #expect(cleared.metadataBlob == archived.metadataBlob)
        // 같은 바이트는 한 번만 — 메타데이터 하나 + 잉크 하나.
        #expect(payload.manifest.blobs.count == 2)
    }

    @Test("같은 바이트는 장이 달라도 blob 하나다 — 장은 권 → 장 순서로 담는다")
    func sameBytesAreWrittenOnceAcrossChapters() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 출애굽기 3장 · 창세기 2장 · 창세기 1장에 같은 잉크 · 같은 메타데이터.
        let ink = BackupExportSample.ink("같은 필기")
        try harness.seed([
            BackupExportRowSeed(chapter: BackupExportSample.exodus3, verse: 1, rowUUID: "EXO", lineData: ink, layoutMetadataData: BackupExportSample.metadata),
            BackupExportRowSeed(chapter: BackupExportSample.genesis2, verse: 1, rowUUID: "GEN2", lineData: ink, layoutMetadataData: BackupExportSample.metadata),
            BackupExportRowSeed(chapter: BackupExportSample.genesis1, verse: 1, rowUUID: "GEN1", lineData: ink, layoutMetadataData: BackupExportSample.metadata)
        ])
        let progress = BackupProgressRecorder()

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { progress.record($0) }
        let payload = try harness.open(result)

        // Then
        #expect(payload.manifest.blobs.map(\.name).sorted() == [BackupFormat.sha256Hex(ink), BackupFormat.sha256Hex(BackupExportSample.metadata)].sorted())
        #expect(payload.items.compactMap(\.source.rowKey) == ["GEN1", "GEN2", "EXO"])
        #expect(payload.items.map(\.verse.book) == ["GEN", "GEN", "EXO"])
        let allCurrent = payload.items.allSatisfy { $0.isCurrent }
        #expect(allCurrent)
        // 진행은 장 단위다 — 시작 0 다음 장마다 하나.
        #expect(progress.events == [0, 1, 2, 3].map { BackupProgress(done: $0, total: 3) })
    }

    @Test("백업 전용 조회 — 행이 있는 장(권 → 장 순), 그 장의 행 원본과 세대를 함께 준다")
    func backupQueriesReadOriginalRowsWithGeneration() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 세 장의 행, 권 이름을 알 수 없는 행, 장이 없는 행, 절이 없는 행.
        let genesis1 = [
            BackupExportRowSeed(verse: 2, rowUUID: "B", lineData: BackupExportSample.ink("b"), layoutMetadataData: BackupExportSample.metadata),
            BackupExportRowSeed(verse: 1, rowUUID: "Z", translation: nil, lineData: nil, layoutMetadataData: nil),
            BackupExportRowSeed(verse: 1, rowUUID: nil, businessID: "1-01Genesis.txt.1.1.100", drawingVersion: 1, lineData: BackupExportSample.ink("a"), layoutMetadataData: nil)
        ]
        var unknownTitle = BackupExportRowSeed(verse: 1, rowUUID: "UNKNOWN-TITLE", lineData: BackupExportSample.ink("u"), layoutMetadataData: nil)
        unknownTitle.titleNameOverride = "9-99Unknown.txt"
        var noChapter = BackupExportRowSeed(verse: 1, rowUUID: "NO-CHAPTER", lineData: BackupExportSample.ink("c"), layoutMetadataData: nil)
        noChapter.dropsChapter = true
        let noVerse = BackupExportRowSeed(verse: nil, rowUUID: "NO-VERSE", lineData: BackupExportSample.ink("v"), layoutMetadataData: nil)
        try harness.seed(genesis1 + [
            BackupExportRowSeed(chapter: BackupExportSample.exodus3, verse: 1, rowUUID: "EXO", lineData: nil, layoutMetadataData: nil),
            BackupExportRowSeed(chapter: BackupExportSample.genesis2, verse: 4, rowUUID: "GEN2", lineData: nil, layoutMetadataData: nil),
            unknownTitle, noChapter, noVerse
        ])

        // When
        let chapters = try await harness.database.backupChapters()
        let load = try await harness.database.backupRows(chapter: BackupExportSample.genesis1)

        // Then: 장은 권 → 장 순서, 절 키를 만들 수 없는 행은 담지 않는다.
        #expect(chapters == [BackupExportSample.genesis1, BackupExportSample.genesis2, BackupExportSample.exodus3])
        #expect(load.generation == DrawingStoreGeneration(raw: 0))
        // 원본 그대로 — 절 → 행 키 순. 절이 없는 행은 빠진다.
        let expected = genesis1.map(\.record).sorted { ($0.verse, $0.rowKey) < ($1.verse, $1.rowKey) }
        #expect(load.rows == expected)
        #expect(load.rows.first(where: { $0.rowKey == "Z" })?.translation == nil)
        #expect(load.rows.first(where: { $0.rowKey == "1-01Genesis.txt.1.1.100" })?.rowUUID == nil)

        // 「모든 필사 삭제」 뒤에는 세대가 오르고 행이 없다.
        try await harness.database.eraseAllDrawingRows()
        let erased = try await harness.database.backupRows(chapter: BackupExportSample.genesis1)
        #expect(erased.generation == DrawingStoreGeneration(raw: 1))
        #expect(erased.rows.isEmpty)
        #expect(try await harness.database.backupChapters().isEmpty)
    }
}
