//
//  BackupFormatSupportTesting.swift
//  DomainTest
//
//  필사 백업 형식 — 항목별 지원 판정(설계 §5-1 unsupported). 모르는 형식은 파일을 거부하지 않고 그 항목만 건너뛴다.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 형식 — 항목 지원 판정")
struct BackupFormatSupportTesting {

    private func item(
        translation: String? = "NKRV",
        book: String = "GEN",
        chapter: Int = 1,
        verse: Int = 1,
        drawingVersion: Int? = 3,
        ink: Data? = BackupFormatSample.inkVerse1,
        metadata: Data? = BackupFormatSample.metadata
    ) -> BackupItem {
        BackupFormatSample.rowItem(
            rowKey: "ROW", verse: verse, drawingVersion: drawingVersion, ink: ink, metadata: metadata, isCurrent: true,
            translation: translation, book: book, chapter: chapter
        )
    }

    /// 메타데이터 blob 을 표본 바이트에서 찾는다(폴더 없이).
    private func reason(_ item: BackupItem, metadata: Data?) -> BackupUnsupportedReason? {
        BackupItemSupport.reason(item) { name in
            guard let metadata, name == BackupFormat.sha256Hex(metadata) else { return nil }
            return metadata
        }
    }

    @Test("번역 nil · NKRV, 좌표 형식 nil · 1 · 2 · 3 은 지원한다")
    func knownValuesAreSupported() {
        #expect(reason(item(translation: nil), metadata: BackupFormatSample.metadata) == nil)
        #expect(reason(item(translation: "NKRV"), metadata: BackupFormatSample.metadata) == nil)
        for version in [nil, 1, 2] as [Int?] {
            #expect(reason(item(drawingVersion: version, metadata: nil), metadata: nil) == nil)
        }
        #expect(reason(item(drawingVersion: 3), metadata: BackupFormatSample.metadata) == nil)
    }

    @Test("모르는 번역본")
    func unknownTranslation() {
        #expect(reason(item(translation: "KJV"), metadata: BackupFormatSample.metadata) == .unknownTranslation)
        #expect(reason(item(translation: "nkrv"), metadata: BackupFormatSample.metadata) == .unknownTranslation)
    }

    @Test("모르는 권 코드")
    func unknownBook() {
        #expect(reason(item(book: "TOB"), metadata: BackupFormatSample.metadata) == .unknownBook)
        #expect(reason(item(book: "gen"), metadata: BackupFormatSample.metadata) == .unknownBook)
    }

    @Test("모르는 좌표 형식")
    func unknownDrawingVersion() {
        #expect(reason(item(drawingVersion: 4, metadata: nil), metadata: nil) == .unknownDrawingVersion)
        #expect(reason(item(drawingVersion: 0, metadata: nil), metadata: nil) == .unknownDrawingVersion)
    }

    @Test("v3 잉크 항목의 메타데이터 blob 이 있는데 풀리지 않으면 지원 밖")
    func undecodableMetadataForInkedV3() {
        // 뒤 버전의 metadataSchemaVersion 이거나 깨진 바이트다(정책 §6-2).
        #expect(reason(item(metadata: BackupFormatSample.brokenMetadata), metadata: BackupFormatSample.brokenMetadata) == .undecodableMetadata)
        // v2 는 메타데이터를 해석하지 않는다.
        #expect(reason(item(drawingVersion: 2, metadata: BackupFormatSample.brokenMetadata), metadata: BackupFormatSample.brokenMetadata) == nil)
    }

    /// 내보내기가 원본 그대로 담은 행이고 DrawingCodec 이 첫 밑줄 기준으로 이미 보여 주는 상태다 — 건너뛰면 필기를 잃는다.
    @Test("메타데이터 blob 이 없는 v3 잉크 항목은 지원한다")
    func inkedV3WithoutMetadataIsSupported() {
        #expect(reason(item(metadata: nil), metadata: nil) == nil)
    }

    @Test("0장 · 마지막 장 + 1 · 0절은 범위 밖")
    func outOfRangeLocations() {
        let lastGenesis = BibleTitle.genesis.lastChapter
        #expect(reason(item(chapter: 0), metadata: BackupFormatSample.metadata) == .outOfRange)
        #expect(reason(item(chapter: lastGenesis + 1), metadata: BackupFormatSample.metadata) == .outOfRange)
        #expect(reason(item(book: "OBA", chapter: 2), metadata: BackupFormatSample.metadata) == .outOfRange)
        #expect(reason(item(verse: 0), metadata: BackupFormatSample.metadata) == .outOfRange)
        #expect(reason(item(verse: -1), metadata: BackupFormatSample.metadata) == .outOfRange)
    }

    @Test("범위 경계값(1장 · 마지막 장 · 1절)은 통과하고, 절의 상한은 보지 않는다")
    func rangeBoundariesPass() {
        #expect(reason(item(chapter: 1, verse: 1), metadata: BackupFormatSample.metadata) == nil)
        #expect(reason(item(chapter: BibleTitle.genesis.lastChapter), metadata: BackupFormatSample.metadata) == nil)
        #expect(reason(item(book: "OBA", chapter: 1), metadata: BackupFormatSample.metadata) == nil)
        #expect(reason(item(book: "PSA", chapter: 150), metadata: BackupFormatSample.metadata) == nil)
        // 절의 상한은 본문을 읽어야 해 이 판정이 보지 않는다.
        #expect(reason(item(verse: 999), metadata: BackupFormatSample.metadata) == nil)
    }

    /// 비운 항목은 판정기의 비운 항목 규칙이 다룬다 — 메타데이터를 요구하지 않는다.
    @Test("비운 v3 항목은 메타데이터가 없거나 깨져도 지원 밖이 아니다")
    func clearedItemsAreNotUnsupported() {
        #expect(reason(item(ink: nil, metadata: nil), metadata: nil) == nil)
        #expect(reason(item(ink: nil, metadata: BackupFormatSample.brokenMetadata), metadata: BackupFormatSample.brokenMetadata) == nil)
    }

    @Test("이유는 번역본 → 권 → 범위 → 좌표 형식 → 메타데이터 순으로 하나다")
    func firstReasonWins() {
        #expect(reason(item(translation: "KJV", book: "TOB", chapter: 0, drawingVersion: 9), metadata: nil) == .unknownTranslation)
        #expect(reason(item(book: "TOB", chapter: 0, drawingVersion: 9), metadata: nil) == .unknownBook)
        #expect(reason(item(chapter: 0, drawingVersion: 9), metadata: nil) == .outOfRange)
        #expect(reason(item(drawingVersion: 9, metadata: BackupFormatSample.brokenMetadata), metadata: BackupFormatSample.brokenMetadata) == .unknownDrawingVersion)
    }

    @Test("blob 폴더에서 메타데이터를 읽어 판정한다")
    func readsMetadataFromTheBlobDirectory() throws {
        // Given
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeBlobs([BackupFormatSample.inkVerse1, BackupFormatSample.metadata, BackupFormatSample.brokenMetadata])

        // When · Then
        #expect(BackupItemSupport.reason(item(), blobDirectory: fixture.blobDirectory) == nil)
        #expect(BackupItemSupport.reason(item(metadata: BackupFormatSample.brokenMetadata), blobDirectory: fixture.blobDirectory) == .undecodableMetadata)
        // 파일이 없으면 풀리지 않는 것과 같다.
        #expect(BackupItemSupport.reason(item(metadata: Data("없는 blob".utf8)), blobDirectory: fixture.blobDirectory) == .undecodableMetadata)
    }

    @Test("표본 백업의 항목은 모두 지원한다")
    func sampleItemsAreSupported() throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeSample()
        let payload = try BackupPayload.load(rootDirectory: fixture.root, limits: .default)

        #expect(payload.items.allSatisfy { BackupItemSupport.reason($0, blobDirectory: payload.blobDirectory) == nil })
    }
}
