//
//  BackupFormatTestSupport.swift
//  DomainTest
//
//  필사 백업 형식 시험의 공용 표본 — 고정 바이트 잉크 · 메타데이터와 시험마다 따로 만드는 풀린 백업 폴더.
//

import Foundation

@testable import Domain

/// 고정 표본. 잉크는 `PKDrawing` 이 아니라 고정 바이트다 — `PKDrawing` 바이트는 만들 때마다 달라진다.
enum BackupFormatSample {
    /// 소수 초가 있는 시각 — `deferredToDate` 가 손실 없이 왕복해야 한다.
    static let createdAt = Date(timeIntervalSinceReferenceDate: 812_613_600.123_456_7)
    static let rowCreatedAt = Date(timeIntervalSinceReferenceDate: 811_600_400.5)
    static let rowUpdatedAt = Date(timeIntervalSinceReferenceDate: 811_600_496.789)
    static let clearedAt = Date(timeIntervalSinceReferenceDate: 812_460_000.25)
    static let archivedAt = Date(timeIntervalSinceReferenceDate: 812_023_200)
    static let draftSavedAt = Date(timeIntervalSinceReferenceDate: 812_600_000)

    /// `DrawingLayoutMetadata.decode` 로 풀리는 메타데이터.
    static let metadata = Data("""
    {"metadataSchemaVersion":1,"baseWritingWidth":300,"baseWritingHeight":400,\
    "baseUnderlineAnchors":[0,30],"layoutSignature":"cl2-abc"}
    """.utf8)
    /// 풀리지 않는 메타데이터.
    static let brokenMetadata = Data("깨진 메타데이터".utf8)

    static let inkVerse1 = Data("ink-genesis-1-1".utf8)
    static let inkVerse2Archived = Data("ink-genesis-1-2-archived".utf8)
    static let inkVerse3 = Data("ink-genesis-1-3-v2".utf8)
    static let inkDraft = Data("ink-genesis-1-4-draft".utf8)

    /// 행 항목 하나 — 지문 · id · blob 이름을 원본 바이트에서 만든다(내보내기와 같은 규칙).
    static func rowItem(
        rowKey: String,
        verse: Int,
        drawingVersion: Int?,
        ink: Data?,
        metadata: Data?,
        isCurrent: Bool,
        createdAt: Date? = rowCreatedAt,
        updatedAt: Date? = rowUpdatedAt,
        translation: String? = "NKRV",
        book: String = "GEN",
        chapter: Int = 1
    ) -> BackupItem {
        let fingerprint = ink.map {
            VerseContentFingerprint.make(lineData: $0, drawingVersion: drawingVersion, layoutMetadataBlob: metadata)
        }
        return BackupItem(
            id: BackupItemID.make(kind: .row, sourceKey: rowKey, fingerprint: fingerprint),
            kind: .row,
            verse: BackupVerseKey(translation: translation, book: book, chapter: chapter, verse: verse),
            drawingVersion: drawingVersion,
            inkBlob: ink.map(BackupFormat.sha256Hex),
            metadataBlob: metadata.map(BackupFormat.sha256Hex),
            fingerprint: fingerprint,
            isCurrent: isCurrent,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: BackupItemSource(titleName: BibleTitle.genesis.rawValue, rowKey: rowKey)
        )
    }

    /// 초안 항목 하나.
    static func draftItem(verse: Int, ink: Data, metadata: Data?, revision: Int) -> BackupItem {
        let fingerprint = VerseContentFingerprint.make(lineData: ink, drawingVersion: 3, layoutMetadataBlob: metadata)
        let sourceKey = BackupItemID.draftSourceKey(
            draftScope: BackupItemSource.DraftScope.local.rawValue,
            sessionID: "SESSION-1",
            translation: "NKRV",
            title: BibleTitle.genesis.rawValue,
            chapter: 1,
            verse: verse,
            revision: revision
        )
        return BackupItem(
            id: BackupItemID.make(kind: .draft, sourceKey: sourceKey, fingerprint: fingerprint),
            kind: .draft,
            verse: BackupVerseKey(translation: "NKRV", title: .genesis, chapter: 1, verse: verse),
            drawingVersion: 3,
            inkBlob: BackupFormat.sha256Hex(ink),
            metadataBlob: metadata.map(BackupFormat.sha256Hex),
            fingerprint: fingerprint,
            isCurrent: true,
            createdAt: nil,
            updatedAt: draftSavedAt,
            source: BackupItemSource(
                titleName: BibleTitle.genesis.rawValue,
                draftScope: BackupItemSource.DraftScope.local.rawValue,
                draftRevision: revision
            )
        )
    }

    /// 설계 §2-9 예시와 같은 모양 — 1절 대표(v3) · 2절 「비운 현재 + 잉크 보관」(메타데이터 공유) · 3절 v2(메타데이터 없음) · 4절 초안.
    static func items() -> [BackupItem] {
        [
            rowItem(rowKey: "5C0E5D0B-2F7A-4C55-9D51-0E1B9C2E7A10", verse: 1, drawingVersion: 3, ink: inkVerse1, metadata: metadata, isCurrent: true),
            rowItem(
                rowKey: "A1F3C6E2-0B4D-4E8A-9F17-3C2D5B6A7E80", verse: 2, drawingVersion: 3, ink: nil, metadata: metadata,
                isCurrent: true, updatedAt: clearedAt
            ),
            rowItem(
                rowKey: "D04B9A31-6C2E-4F5D-8B07-1E9A2C3D4F56", verse: 2, drawingVersion: 3, ink: inkVerse2Archived, metadata: metadata,
                isCurrent: false, updatedAt: archivedAt
            ),
            rowItem(rowKey: "1-01Genesis.txt.1.3.1773450123", verse: 3, drawingVersion: 2, ink: inkVerse3, metadata: nil, isCurrent: true),
            draftItem(verse: 4, ink: inkDraft, metadata: metadata, revision: 7)
        ]
    }

    /// 표본 항목이 가리키는 blob 바이트(같은 바이트는 한 번).
    static func blobs() -> [Data] {
        [inkVerse1, metadata, inkVerse2Archived, inkVerse3, inkDraft]
    }

    /// 항목 · blob 에 맞는 manifest.
    static func manifest(items: [BackupItem], blobs: [Data]) -> BackupManifest {
        let entries = blobs.map(BackupBlobEntry.init(bytes:)).sorted { $0.name < $1.name }
        let rows = items.filter { $0.kind == .row }.count
        return BackupManifest(
            backupID: "8E5D2C1A-4B7F-4F0E-9C3D-6A1B2E3F4D5C",
            createdAt: createdAt,
            appVersion: "2.1.0",
            scope: BackupScope(rows: true, drafts: true),
            counts: BackupCounts(rows: rows, drafts: items.count - rows, blobs: entries.count),
            blobs: entries
        )
    }
}

/// 시험 하나가 쓰는 풀린 백업 폴더(`FileManager.temporaryDirectory/BackupFormatTesting/<UUID>/`). 시험이 끝나면 `remove()` 로 지운다.
struct BackupFormatFixture {
    let root: URL

    var blobDirectory: URL {
        root.appendingPathComponent(BackupFormat.blobDirectoryName, isDirectory: true)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupFormatTesting", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// blob 을 이름(SHA-256)대로 쓴다.
    func writeBlobs(_ blobs: [Data]) throws {
        for blob in blobs {
            try writeBlob(blob, name: BackupFormat.sha256Hex(blob))
        }
    }

    /// blob 파일 하나를 주어진 이름으로 쓴다(변조 시험은 이름과 다른 바이트를 쓴다).
    func writeBlob(_ bytes: Data, name: String) throws {
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        try bytes.write(to: blobDirectory.appendingPathComponent(name, isDirectory: false))
    }

    /// manifest · items 를 백업 인코더로 쓴다.
    func write(manifest: BackupManifest, items: [BackupItem]) throws {
        try writeFile(BackupFormat.encoder.encode(manifest), name: BackupFormat.manifestFileName)
        try writeFile(BackupFormat.encoder.encode(items), name: BackupFormat.itemsFileName)
    }

    /// 루트에 파일 하나를 쓴다.
    func writeFile(_ data: Data, name: String) throws {
        try data.write(to: root.appendingPathComponent(name, isDirectory: false))
    }

    /// 표본 전체(blob · manifest · items)를 쓴다.
    func writeSample() throws {
        let items = BackupFormatSample.items()
        let blobs = BackupFormatSample.blobs()
        try writeBlobs(blobs)
        try write(manifest: BackupFormatSample.manifest(items: items, blobs: blobs), items: items)
    }
}
