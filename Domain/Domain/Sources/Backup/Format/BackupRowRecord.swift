//
//  BackupRowRecord.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 전용 행 조회의 결과 하나 — `BibleDrawing` 행의 **원본 필드 · 원본 바이트** 그대로 (설계 §5-3).
///
/// `VerseDrawingSnapshot` 은 캔버스 표시용이라 만든 시각 · 번역 저장값(nil 포함) · `rowUUID` 와 business id 구분 · `isPresent` 원본(nil 포함)이
/// 없고 메타데이터가 이미 해석돼 있어, 원본 보존 계약을 지킬 수 없다. 내보내기 · 판정 · 복원 쓰기가 **같은 변환**(`SwiftDatabaseActor+Backup.swift`)
/// 으로 만든 이 값으로 견준다 — 지문이 한쪽만 다시 인코딩되면 같은 필기를 다른 것으로 본다.
public struct BackupRowRecord: Codable, Equatable, Sendable {
    /// 도메인 행 키 — `rowUUID` 가 비어 있지 않으면 그것, 아니면 business id(`BibleDrawing.rowKey` 와 같은 규칙).
    public let rowKey: String
    /// 행 식별자(§8-7). 1.3.0 행은 nil.
    public let rowUUID: String?
    /// business `id`(`BibleDrawing.id`) 원본.
    public let businessID: String?
    /// `BibleTitle.rawValue` 원문.
    public let titleName: String
    /// 장(`titleChapter`).
    public let chapter: Int
    /// 절.
    public let verse: Int
    /// 번역 저장값 그대로. 없으면 nil — NKRV 로 채우지 않는다.
    public let translation: String?
    /// `isPresent` 원본(nil 포함). 대표 판정에서 nil 은 false 다.
    public let isPresent: Bool?
    /// `creationDate` 원본.
    public let creationDate: Date?
    /// `updateDate` 원본.
    public let updateDate: Date?
    /// 좌표 형식 원본.
    public let drawingVersion: Int?
    /// `lineData` 원본 바이트. 비운 행이면 nil.
    public let lineData: Data?
    /// `layoutMetadataData` 원본 바이트(해석하지 않는다).
    public let layoutMetadataData: Data?
    /// 잉크가 있을 때만 원본 바이트로 만든 내용 지문(`VerseContentFingerprint.make`). 비운 행은 nil.
    public let contentFingerprint: String?

    /// 원본 필드로 만든다. `rowKey` 와 `contentFingerprint` 는 여기서 계산한다(호출부마다 규칙이 갈리지 않게).
    public init(
        rowUUID: String?,
        businessID: String?,
        titleName: String,
        chapter: Int,
        verse: Int,
        translation: String?,
        isPresent: Bool?,
        creationDate: Date?,
        updateDate: Date?,
        drawingVersion: Int?,
        lineData: Data?,
        layoutMetadataData: Data?
    ) {
        if let rowUUID, !rowUUID.isEmpty {
            self.rowKey = rowUUID
        } else {
            self.rowKey = businessID ?? ""
        }
        self.rowUUID = rowUUID
        self.businessID = businessID
        self.titleName = titleName
        self.chapter = chapter
        self.verse = verse
        self.translation = translation
        self.isPresent = isPresent
        self.creationDate = creationDate
        self.updateDate = updateDate
        self.drawingVersion = drawingVersion
        self.lineData = lineData
        self.layoutMetadataData = layoutMetadataData
        self.contentFingerprint = lineData.map {
            VerseContentFingerprint.make(lineData: $0, drawingVersion: drawingVersion, layoutMetadataBlob: layoutMetadataData)
        }
    }

    /// 잉크가 있는 행인가 — 없으면 비운 행.
    public var hasInk: Bool { lineData != nil }

    private enum CodingKeys: String, CodingKey {
        case rowUUID, businessID, titleName, chapter, verse, translation, isPresent
        case creationDate, updateDate, drawingVersion, lineData, layoutMetadataData
    }

    /// 원본 필드만 읽고 `rowKey` · `contentFingerprint` 는 다시 계산한다 — 저장된 계산값을 믿지 않는다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rowUUID: try container.decodeIfPresent(String.self, forKey: .rowUUID),
            businessID: try container.decodeIfPresent(String.self, forKey: .businessID),
            titleName: try container.decode(String.self, forKey: .titleName),
            chapter: try container.decode(Int.self, forKey: .chapter),
            verse: try container.decode(Int.self, forKey: .verse),
            translation: try container.decodeIfPresent(String.self, forKey: .translation),
            isPresent: try container.decodeIfPresent(Bool.self, forKey: .isPresent),
            creationDate: try container.decodeIfPresent(Date.self, forKey: .creationDate),
            updateDate: try container.decodeIfPresent(Date.self, forKey: .updateDate),
            drawingVersion: try container.decodeIfPresent(Int.self, forKey: .drawingVersion),
            lineData: try container.decodeIfPresent(Data.self, forKey: .lineData),
            layoutMetadataData: try container.decodeIfPresent(Data.self, forKey: .layoutMetadataData)
        )
    }

    /// 원본 필드만 쓴다.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rowUUID, forKey: .rowUUID)
        try container.encodeIfPresent(businessID, forKey: .businessID)
        try container.encode(titleName, forKey: .titleName)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(verse, forKey: .verse)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(isPresent, forKey: .isPresent)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(updateDate, forKey: .updateDate)
        try container.encodeIfPresent(drawingVersion, forKey: .drawingVersion)
        try container.encodeIfPresent(lineData, forKey: .lineData)
        try container.encodeIfPresent(layoutMetadataData, forKey: .layoutMetadataData)
    }
}

extension BackupRowRecord: DrawingRepresentativeCandidate {
    /// `isPresent` nil 은 false — `BibleDrawing` 의 대표 판정과 같다.
    public var representativeIsPresent: Bool { isPresent ?? false }
    /// `updateDate` 원본.
    public var representativeUpdateDate: Date? { updateDate }
    /// 동률 tie-break 행 키.
    public var representativeRowKey: String { rowKey }
}

/// 장 하나의 백업 전용 조회 결과 — 행과 저장소 세대를 **같은 actor 구간에서** 읽는다(따로 읽으면 그 사이의 전체 삭제를 놓친다).
///
/// 세대(`DrawingStoreGeneration`)는 앱 실행 동안만 뜻이 있어 파일에 쓰지 않는다 — 그래서 이 타입은 Codable 이 아니다.
public struct BackupRowLoad: Equatable, Sendable {
    /// 그 장의 모든 행(현재 · 보관 · 비운 행).
    public let rows: [BackupRowRecord]
    /// 읽은 때의 저장소 세대.
    public let generation: DrawingStoreGeneration

    /// 조회 결과를 묶는다.
    public init(rows: [BackupRowRecord], generation: DrawingStoreGeneration) {
        self.rows = rows
        self.generation = generation
    }
}
