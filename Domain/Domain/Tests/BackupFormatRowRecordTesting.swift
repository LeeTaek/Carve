//
//  BackupFormatRowRecordTesting.swift
//  DomainTest
//
//  필사 백업 형식 — 백업 전용 행 조회 값(설계 §5-3): 행 키 · 원본 바이트 지문 · 대표 판정.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 형식 — 행 기록")
struct BackupFormatRowRecordTesting {

    private func record(
        rowUUID: String? = nil,
        businessID: String? = "1-01Genesis.txt.1.1.100",
        isPresent: Bool? = true,
        updateDate: Date? = Date(timeIntervalSinceReferenceDate: 100),
        drawingVersion: Int? = 3,
        lineData: Data? = BackupFormatSample.inkVerse1,
        layoutMetadataData: Data? = BackupFormatSample.metadata
    ) -> BackupRowRecord {
        BackupRowRecord(
            rowUUID: rowUUID,
            businessID: businessID,
            titleName: BibleTitle.genesis.rawValue,
            chapter: 1,
            verse: 1,
            translation: nil,
            isPresent: isPresent,
            creationDate: Date(timeIntervalSinceReferenceDate: 50),
            updateDate: updateDate,
            drawingVersion: drawingVersion,
            lineData: lineData,
            layoutMetadataData: layoutMetadataData
        )
    }

    @Test("행 키는 rowUUID, 없거나 비었으면 business id 다")
    func rowKeyFollowsTheBibleDrawingRule() {
        #expect(record(rowUUID: "UUID-1").rowKey == "UUID-1")
        #expect(record(rowUUID: nil).rowKey == "1-01Genesis.txt.1.1.100")
        #expect(record(rowUUID: "").rowKey == "1-01Genesis.txt.1.1.100")
        #expect(record(rowUUID: nil, businessID: nil).rowKey == "")
        #expect(record(rowUUID: "UUID-1").representativeRowKey == "UUID-1")
    }

    @Test("지문은 잉크가 있을 때만, 원본 바이트로 만든다")
    func fingerprintOnlyWithInkFromRawBytes() {
        // 잉크 없음 — 메타데이터가 남아 있어도 nil
        #expect(record(lineData: nil).contentFingerprint == nil)
        #expect(record(lineData: nil).hasInk == false)

        // 잉크 있음 — 원본 바이트 그대로의 지문
        #expect(
            record().contentFingerprint
                == VerseContentFingerprint.make(lineData: BackupFormatSample.inkVerse1, drawingVersion: 3, layoutMetadataBlob: BackupFormatSample.metadata)
        )
        // 풀리지 않는 메타데이터도 해석해 다시 인코딩하지 않고 원본 바이트로 넣는다 — 다른 깨진 값과 구분된다.
        let broken = record(layoutMetadataData: BackupFormatSample.brokenMetadata).contentFingerprint
        let otherBroken = record(layoutMetadataData: Data("또 다른 깨진 값".utf8)).contentFingerprint
        #expect(
            broken
                == VerseContentFingerprint.make(
                    lineData: BackupFormatSample.inkVerse1, drawingVersion: 3, layoutMetadataBlob: BackupFormatSample.brokenMetadata
                )
        )
        #expect(broken != otherBroken)
        // 좌표 형식이 다르면 다른 내용이다.
        #expect(record(drawingVersion: 2).contentFingerprint != record(drawingVersion: 3).contentFingerprint)
    }

    @Test("대표는 isPresent 행 중 최신, 동률이면 행 키 사전순")
    func representativePrefersPresentNewest() {
        let older = record(rowUUID: "A", updateDate: Date(timeIntervalSinceReferenceDate: 100))
        let newer = record(rowUUID: "B", updateDate: Date(timeIntervalSinceReferenceDate: 200))
        let newestArchived = record(rowUUID: "C", isPresent: false, updateDate: Date(timeIntervalSinceReferenceDate: 300))
        let tieLater = record(rowUUID: "Z", updateDate: Date(timeIntervalSinceReferenceDate: 200))

        #expect(DrawingRepresentativeRule.pick([newestArchived, older, newer, tieLater])?.rowKey == "B")
    }

    @Test("isPresent nil 은 false 로 본다")
    func missingIsPresentCountsAsFalse() {
        let unknown = record(rowUUID: "A", isPresent: nil, updateDate: Date(timeIntervalSinceReferenceDate: 300))
        let present = record(rowUUID: "B", isPresent: true, updateDate: Date(timeIntervalSinceReferenceDate: 100))

        #expect(unknown.representativeIsPresent == false)
        #expect(DrawingRepresentativeRule.pick([unknown, present])?.rowKey == "B")
    }

    /// 「지우기」 뒤의 절 — 비운 대표 행(present)이 잉크 있는 보관 행보다 앞선다. 비운 대표를 빼면 보관 행이 대표로 올라가 지운 필기가 되살아난다.
    @Test("비운 현재 행이 잉크 있는 보관 행보다 대표다")
    func clearedPresentRowStaysRepresentative() {
        let cleared = record(rowUUID: "CLEARED", isPresent: true, updateDate: Date(timeIntervalSinceReferenceDate: 100), lineData: nil)
        let archived = record(rowUUID: "ARCHIVED", isPresent: false, updateDate: Date(timeIntervalSinceReferenceDate: 200))

        let representative = DrawingRepresentativeRule.pick([archived, cleared])
        #expect(representative?.rowKey == "CLEARED")
        #expect(representative?.contentFingerprint == nil)
    }

    @Test("isPresent 행이 없으면 전체에서 최신, nil 시각은 가장 이르다")
    func withoutPresentRowsPicksNewestOverall() {
        let undated = record(rowUUID: "A", isPresent: false, updateDate: nil)
        let dated = record(rowUUID: "B", isPresent: false, updateDate: Date(timeIntervalSinceReferenceDate: 1))

        #expect(DrawingRepresentativeRule.pick([undated, dated])?.rowKey == "B")
        #expect(DrawingRepresentativeRule.pick([BackupRowRecord]()) == nil)
    }

    @Test("Codable 왕복 — 계산값(행 키 · 지문)은 원본 필드로 다시 만든다")
    func codableRoundTripRecomputesDerivedValues() throws {
        let original = record(rowUUID: "UUID-1")

        let bytes = try BackupFormat.encoder.encode(original)
        let decoded = try BackupFormat.decoder.decode(BackupRowRecord.self, from: bytes)

        #expect(decoded == original)
        #expect(!(String(bytes: bytes, encoding: .utf8) ?? "").contains("contentFingerprint"))
    }

    @Test("장 조회 결과는 행과 세대를 함께 든다")
    func rowLoadCarriesGeneration() {
        let load = BackupRowLoad(rows: [record()], generation: DrawingStoreGeneration(raw: 3))

        #expect(load.rows.count == 1)
        #expect(load.generation == DrawingStoreGeneration(raw: 3))
        #expect(load != BackupRowLoad(rows: [record()], generation: DrawingStoreGeneration(raw: 4)))
    }
}
