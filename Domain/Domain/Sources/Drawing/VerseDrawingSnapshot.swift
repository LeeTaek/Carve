//
//  VerseDrawingSnapshot.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

// MARK: - 행 식별자 (설계 §5 · §8-7)

/// `BibleDrawing` 행 식별자. SwiftData `PersistentIdentifier` 를 Feature 에 노출하지 않기 위한 도메인 키.
///
/// | 대상 | `raw` 의 값 |
/// |---|---|
/// | 신규 V4 행 | 저장 **전에** 발급한 UUID (`issue()`). 그대로 `BibleDrawing.rowUUID` 에 기록된다 |
/// | 기존 legacy 행 | business `id` (`"<권>.<장>.<절>.<timestamp>"`). **쓰기 갱신 없음** (비파괴, §8-7) |
///
/// 두 종류를 구분하지 않고 하나의 키로 다루는 이유는 pending 큐(§8-3)가 rowID 하나로 coalescing 하기 때문이다.
public struct BibleDrawingRowID: Hashable, Sendable, Codable, Comparable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    /// 신규 행용 식별자를 **저장 전에** 발급한다 (§8-7 "신규 행의 rowID는 저장 전에 발급한다").
    /// - Returns: UUID 기반 식별자.
    public static func issue() -> BibleDrawingRowID {
        BibleDrawingRowID(raw: UUID().uuidString)
    }

    /// 결정적 tie-break 용 사전순 (§8-7 `mainDrawing()` 규칙).
    public static func < (lhs: BibleDrawingRowID, rhs: BibleDrawingRowID) -> Bool {
        lhs.raw < rhs.raw
    }
}

// MARK: - DB 에서 읽어온 행 (설계 §5)

/// DB 에서 읽어온 절 하나의 저장 상태 (행 단위).
///
/// 절당 여러 행(필사 회차, U2)이 있을 수 있으므로 **행마다 하나**다. 어느 행을 캔버스에 합성할지는
/// `representative()` 가 결정적으로 고른다 (§8-7).
public struct VerseDrawingSnapshot: Equatable, Sendable {
    public let verse: Int
    public let rowID: BibleDrawingRowID
    /// 이 행이 현재 대표(main)로 표시돼 있는지. CloudKit 충돌로 한 절에 여럿이 true 일 수 있다.
    public let isPresent: Bool
    public let updateDate: Date?
    /// `PKDrawing.dataRepresentation()`. 행은 있지만 내용이 비워진 경우(`clear` 이후) nil.
    ///
    /// 설계 §5 의 DTO 는 non-optional 이지만, "빈 Data" 는 유효한 PencilKit 인코딩이 아니라
    /// 디코드가 실패하므로 **없음을 nil 로 구분**한다.
    public let lineData: Data?
    /// 좌표 형식의 단일 진실 (`BibleDrawing.drawingVersion` 그대로).
    /// nil / 1 = legacy, 2 = verse-local + top-left, 3 = verse-local + 첫 밑줄 anchor.
    public let drawingVersion: Int?
    /// `drawingVersion == 3` 일 때만 존재.
    public let metadata: DrawingLayoutMetadata?

    public init(
        verse: Int,
        rowID: BibleDrawingRowID,
        isPresent: Bool,
        updateDate: Date?,
        lineData: Data?,
        drawingVersion: Int?,
        metadata: DrawingLayoutMetadata?
    ) {
        self.verse = verse
        self.rowID = rowID
        self.isPresent = isPresent
        self.updateDate = updateDate
        self.lineData = lineData
        self.drawingVersion = drawingVersion
        self.metadata = metadata
    }

    /// 좌표 형식이 확정된 행인가 (`drawingVersion == 3` + metadata).
    public var hasVersionedLayout: Bool {
        drawingVersion == 3 && metadata != nil
    }
}

// MARK: - 저장 명령 (설계 §5 · §8-2 · §8-7)

/// 저장 명령 — 절이 아니라 **행**을 주소지정한다 (U2: 히스토리 유지).
public enum VerseDrawingMutation: Equatable, Sendable {
    /// 활성 행의 내용을 교체. `data` 는 그 절의 **완전한** 획 집합이다 (delta 가 아님, §8-3).
    case replace(verse: Int, rowID: BibleDrawingRowID, data: Data, metadata: DrawingLayoutMetadata)
    /// 활성 행의 내용을 비움. **행을 삭제하지 않는다** (§8-7 — 삭제하면 과거 회차가 승격돼 지운 획이 되살아난다).
    case clear(verse: Int, rowID: BibleDrawingRowID)
    /// 해당 절에 행이 하나도 없을 때. `rowID` 는 **저장 전에 미리 발급**된 값이다 (§8-7).
    case create(verse: Int, rowID: BibleDrawingRowID, data: Data, metadata: DrawingLayoutMetadata)

    public var verse: Int {
        switch self {
        case .replace(let verse, _, _, _), .clear(let verse, _), .create(let verse, _, _, _): verse
        }
    }

    /// 세 케이스 모두 rowID 를 가지므로 non-optional — pending 큐의 단일 키다 (§8-3).
    public var rowID: BibleDrawingRowID {
        switch self {
        case .replace(_, let rowID, _, _), .clear(_, let rowID), .create(_, let rowID, _, _): rowID
        }
    }
}

// MARK: - 저장 실패

/// `DrawingRepository.apply` 의 실패. batch 는 전부 성공하거나 전부 실패한다 (P8).
public enum DrawingRepositoryError: Error, Equatable, Sendable {
    /// `replace` 가 가리킨 행이 없다.
    case rowNotFound(BibleDrawingRowID)
    /// metadata blob 인코딩 실패.
    case metadataEncodingFailed(verse: Int)
    /// SwiftData 저장 실패. 원인 설명만 담는다.
    case persistenceFailed(String)
}
