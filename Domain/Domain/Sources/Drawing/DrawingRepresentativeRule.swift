//
//  DrawingRepresentativeRule.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 대표 행 선택에 필요한 최소 정보. `BibleDrawing`(모델)과 `VerseDrawingSnapshot`(DTO)이 같은 규칙을 쓰기 위한 공통 형태.
public protocol DrawingRepresentativeCandidate {
    var representativeIsPresent: Bool { get }
    var representativeUpdateDate: Date? { get }
    /// 동률 tie-break 용 행 키 (`rowUUID` 또는 business `id`).
    var representativeRowKey: String { get }
}

/// 절당 여러 행 중 캔버스에 합성할 **대표 행**을 고르는 결정적 규칙 (설계 §8-7).
///
/// ```
/// 1) isPresent == true 인 행들 중 updateDate 최신
/// 2) 동률이면 rowKey 사전순 (작은 쪽)
/// 3) isPresent 행이 없으면 updateDate 최신 → 동률이면 rowKey 사전순
/// ```
///
/// 이전 `mainDrawing()` 은 `first(where: isPresent)` 라 **배열 순서에 의존**했다. `fetch(chapter:)` 는 verse 로만
/// 정렬하므로 같은 절 안의 순서가 보장되지 않았고, CloudKit 충돌로 `isPresent == true` 행이 둘 이상이면
/// 실행마다 다른 행이 대표가 될 수 있었다. 이 규칙은 입력 순서와 무관하다.
public enum DrawingRepresentativeRule {
    /// 후보 중 대표를 고른다.
    /// - Parameter candidates: 같은 절의 행들. 순서는 결과에 영향을 주지 않는다.
    /// - Returns: 대표 행. 후보가 없으면 nil.
    public static func pick<Candidate: DrawingRepresentativeCandidate>(_ candidates: [Candidate]) -> Candidate? {
        let present = candidates.filter(\.representativeIsPresent)
        let pool = present.isEmpty ? candidates : present
        return pool.min { lhs, rhs in
            // "최신이 먼저" 이므로 updateDate 는 내림차순, 동률이면 rowKey 오름차순.
            let lhsDate = lhs.representativeUpdateDate ?? .distantPast
            let rhsDate = rhs.representativeUpdateDate ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.representativeRowKey < rhs.representativeRowKey
        }
    }
}

extension VerseDrawingSnapshot: DrawingRepresentativeCandidate {
    public var representativeIsPresent: Bool { isPresent }
    public var representativeUpdateDate: Date? { updateDate }
    public var representativeRowKey: String { rowID.raw }
}

public extension Array where Element == VerseDrawingSnapshot {
    /// 같은 절의 행들 중 대표 행 (§8-7 결정적 규칙).
    func representative() -> VerseDrawingSnapshot? {
        DrawingRepresentativeRule.pick(self)
    }

    /// 절별 대표 행. `activeRowIDs`(§8-7) 의 초기값을 만드는 단일 진입점이다.
    func representativesByVerse() -> [Int: VerseDrawingSnapshot] {
        var grouped: [Int: [VerseDrawingSnapshot]] = [:]
        for snapshot in self {
            grouped[snapshot.verse, default: []].append(snapshot)
        }
        return grouped.compactMapValues { $0.representative() }
    }
}
