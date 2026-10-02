//
//  BackupFormatEncodingTesting.swift
//  DomainTest
//
//  필사 백업 형식 — JSON 인코딩 규칙(설계 §2-2): 같은 내용 같은 바이트 · 날짜 무손실 · 모르는 키 무시 · 형식 버전 거부.
//

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Domain

@Suite("백업 형식 — 인코딩")
struct BackupFormatEncodingTesting {

    @Test("형식 상수와 파일 형식 식별자")
    func formatConstantsMatchTheContract() {
        #expect(BackupFormat.formatVersion == 1)
        #expect(BackupFormat.fileExtension == "carvebackup")
        #expect(BackupFormat.typeIdentifier == "kr.co.carve.leetaek.backup")
        #expect(UTType.carveBackup.identifier == BackupFormat.typeIdentifier)
        #expect(BackupItemKind.row.rawValue == "row")
        #expect(BackupItemKind.draft.rawValue == "draft")
        #expect(BackupItemSource.DraftScope.allCases.map(\.rawValue) == ["local", "unverified", "account"])
    }

    @Test("인코딩 → 디코딩 → 인코딩이 같은 바이트이고, 키가 정렬된 한 줄이다")
    func roundTripIsByteStable() throws {
        // Given
        let items = BackupFormatSample.items()
        let manifest = BackupFormatSample.manifest(items: items, blobs: BackupFormatSample.blobs())

        // When
        let manifestBytes = try BackupFormat.encoder.encode(manifest)
        let itemBytes = try BackupFormat.encoder.encode(items)
        let decodedManifest = try BackupFormat.decoder.decode(BackupManifest.self, from: manifestBytes)
        let decodedItems = try BackupFormat.decoder.decode([BackupItem].self, from: itemBytes)

        // Then
        #expect(decodedManifest == manifest)
        #expect(decodedItems == items)
        #expect(try BackupFormat.encoder.encode(decodedManifest) == manifestBytes)
        #expect(try BackupFormat.encoder.encode(decodedItems) == itemBytes)
        let manifestText = String(bytes: manifestBytes, encoding: .utf8) ?? ""
        #expect(manifestText.hasPrefix(#"{"appVersion":"2.1.0","backupID":"#))
        #expect(!manifestText.contains("\n"))
    }

    @Test("날짜는 비트 단위로 왕복한다")
    func datesRoundTripBitForBit() throws {
        // Given — ISO 8601 이면 잃는 소수 초 · 이진 표현이 긴 값 · 음수 · 바로 옆 Double
        let seconds: [Double] = [
            811_600_496.789,
            812_613_600.123_456_7,
            1.0 / 3.0,
            -12_345.000_001,
            Double(812_613_600).nextUp,
            0
        ]
        for value in seconds {
            let date = Date(timeIntervalSinceReferenceDate: value)
            let item = BackupFormatSample.rowItem(
                rowKey: "ROW", verse: 1, drawingVersion: 3, ink: nil, metadata: nil, isCurrent: true, createdAt: date, updatedAt: date
            )

            // When
            let decoded = try BackupFormat.decoder.decode(BackupItem.self, from: BackupFormat.encoder.encode(item))

            // Then
            #expect(decoded.createdAt?.timeIntervalSinceReferenceDate.bitPattern == value.bitPattern)
            #expect(decoded.updatedAt?.timeIntervalSinceReferenceDate.bitPattern == value.bitPattern)
        }
    }

    /// 지운 절의 비운 대표 행 — 잉크 · 지문 없이 메타데이터만 남는다(설계 §2-9 의 2절).
    @Test("비운 행 항목은 inkBlob · fingerprint 키 없이 왕복한다")
    func clearedRowItemRoundTripsWithoutInk() throws {
        // Given
        let cleared = BackupFormatSample.rowItem(
            rowKey: "CLEARED", verse: 2, drawingVersion: 3, ink: nil, metadata: BackupFormatSample.metadata, isCurrent: true
        )

        // When
        let bytes = try BackupFormat.encoder.encode(cleared)
        let decoded = try BackupFormat.decoder.decode(BackupItem.self, from: bytes)

        // Then
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(!text.contains("inkBlob"))
        #expect(!text.contains("fingerprint"))
        #expect(text.contains("metadataBlob"))
        #expect(decoded == cleared)
        #expect(decoded.inkBlob == nil)
        #expect(decoded.fingerprint == nil)
        #expect(decoded.hasInk == false)
        #expect(decoded.id.hasPrefix("row-"))
    }

    @Test("null 과 키 없음은 같게 nil 로 읽는다")
    func explicitNullReadsAsMissing() throws {
        // Given — 번역 미상(null)을 NKRV 로 채우지 않는다
        let json = Data("""
        {"id":"row-1","kind":"row","parents":[],"isCurrent":true,"inkBlob":null,"fingerprint":null,"drawingVersion":null,\
        "verse":{"translation":null,"book":"GEN","chapter":1,"verse":1},"source":{"titleName":"1-01Genesis.txt","rowKey":null}}
        """.utf8)

        // When
        let item = try BackupFormat.decoder.decode(BackupItem.self, from: json)

        // Then
        #expect(item.inkBlob == nil)
        #expect(item.fingerprint == nil)
        #expect(item.drawingVersion == nil)
        #expect(item.verse.translation == nil)
        #expect(item.source.rowKey == nil)
        #expect(item.createdAt == nil)
        #expect(item.updatedAt == nil)
    }

    @Test("모르는 키는 무시한다")
    func unknownKeysAreIgnored() throws {
        // Given — 뒤 버전이 더한 키(최상위 · 안쪽 모두)
        let manifestJSON = Data("""
        {"formatVersion":1,"backupID":"B","createdAt":0,"appVersion":"2.2.0","futureKey":{"a":1},\
        "scope":{"rows":true,"drafts":false,"favorites":true},"counts":{"rows":1,"drafts":0,"blobs":0,"versions":3},"blobs":[]}
        """.utf8)
        let itemsJSON = Data("""
        [{"id":"row-1","kind":"row","parents":[],"isCurrent":false,"lineage":["x"],\
        "verse":{"translation":"NKRV","book":"GEN","chapter":1,"verse":1,"script":"ko"},\
        "source":{"titleName":"1-01Genesis.txt","rowKey":"R","device":"?"}}]
        """.utf8)

        // When
        let manifest = try BackupFormat.decoder.decode(BackupManifest.self, from: manifestJSON)
        let items = try BackupFormat.decoder.decode([BackupItem].self, from: itemsJSON)

        // Then
        #expect(manifest.appVersion == "2.2.0")
        #expect(manifest.scope == BackupScope(rows: true, drafts: false))
        #expect(manifest.counts == BackupCounts(rows: 1, drafts: 0, blobs: 0))
        #expect(items.count == 1)
        #expect(items.first?.verse == BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 1))
        #expect(items.first?.source.rowKey == "R")
    }

    @Test("formatVersion 2 는 나머지 모양과 상관없이 unsupportedFormat 으로 거부한다")
    func formatVersionTwoIsRejected() throws {
        // Given — 같은 모양의 v2, 그리고 키가 바뀐 v2
        let sameShape = Data("""
        {"formatVersion":2,"backupID":"B","createdAt":0,"appVersion":"3.0.0",\
        "scope":{"rows":true,"drafts":true},"counts":{"rows":0,"drafts":0,"blobs":0},"blobs":[]}
        """.utf8)
        let otherShape = Data(#"{"formatVersion":2,"entries":[]}"#.utf8)

        // When · Then
        #expect(throws: BackupFormatError.unsupportedFormat(formatVersion: 2)) {
            try BackupFormat.decoder.decode(BackupManifest.self, from: sameShape)
        }
        #expect(throws: BackupFormatError.unsupportedFormat(formatVersion: 2)) {
            try BackupFormat.decoder.decode(BackupManifest.self, from: otherShape)
        }
    }

    @Test("CanvasFlushOutcome 은 Codable 로 왕복한다")
    func canvasFlushOutcomeRoundTrips() throws {
        let outcomes: [CanvasFlushOutcome] = [.durable, .failed(retryCount: 2), .timedOut]
        let decoded = try BackupFormat.decoder.decode([CanvasFlushOutcome].self, from: BackupFormat.encoder.encode(outcomes))
        #expect(decoded == outcomes)
    }
}
