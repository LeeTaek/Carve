//
//  ChapterLayoutPointQuery.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Foundation

// MARK: - 소유권 판정용 점 조회 (설계 §7-1)

/// 캔버스 좌표 한 점이 어느 절에 속하는지 조회한다.
///
/// `ChapterLayoutBuilder`가 만든 `captureRect`는 이미 `[0, totalHeight]`를 빈틈·겹침 없이 세로로 분할하므로
/// 여기서는 단순 스캔으로 충분하다. 이 파일이 정하는 것은 **경계 위의 점을 누구에게 줄 것인가**뿐이다.
public extension VerseCanvasRegion {
    /// 이 절이 캔버스 좌표 `point`의 소유권을 갖는지 판정한다.
    ///
    /// **경계 규칙 — 세로는 반개구간, 가로는 닫힌 구간.**
    ///
    /// ```
    /// x ∈ [captureRect.minX, captureRect.maxX]   ← 닫힘
    /// y ∈ [captureRect.minY, captureRect.maxY)   ← 반개
    /// ```
    ///
    /// - 세로(y)는 인접 절과 경계를 **공유**한다(`captureRect[i].maxY == captureRect[i+1].minY`).
    ///   그래서 반개구간으로 잡아 경계 위의 점을 **항상 아래(다음 절)** 에 준다.
    ///   두 절이 동시에 소유하거나 어느 절도 소유하지 않는 일이 생기지 않는다.
    /// - 가로(x)는 모든 절이 같은 구간 `[0, writingWidth]`을 쓰고 인접 절이 없다. 즉 x는
    ///   절을 가르는 기준이 아니라 캔버스 안/밖 판정일 뿐이므로, 오른쪽 끝의 점을 잃지 않도록 닫아 둔다.
    ///
    /// - Note: 캔버스 **하단** 경계(`y == totalHeight`)는 인접 절이 없어 이 반개구간 어디에도 속하지 않는다.
    ///         그 한 점은 레이아웃 차원에서 마지막 절에 붙인다 — `ChapterLayout.region(containing:)` 참조.
    ///         따라서 이 메서드만으로 `[0, totalHeight]` 전체가 덮이지는 않는다.
    /// - Parameter point: 캔버스 좌표(원점은 캔버스 좌상단).
    /// - Returns: 소유 여부.
    func capturesPoint(_ point: CGPoint) -> Bool {
        point.x >= captureRect.minX
            && point.x <= captureRect.maxX
            && point.y >= captureRect.minY
            && point.y < captureRect.maxY
    }
}

public extension ChapterLayout {
    /// 캔버스 좌표 한 점을 소유하는 절 영역.
    ///
    /// 설계 §7-1의 "첫 control point → `captureRect` 검색 → ownerVerse" 단계에 해당한다.
    /// 경계 규칙은 `VerseCanvasRegion.capturesPoint(_:)`를 그대로 따르고, 여기에
    /// **캔버스 하단 경계 한 줄만 예외로 닫아** `[0, totalHeight]` 전체를 덮는다.
    ///
    /// - Parameter point: 캔버스 좌표.
    /// - Returns: 소유 절 영역. 캔버스 밖이면 nil.
    func region(containing point: CGPoint) -> VerseCanvasRegion? {
        if let hit = regions.first(where: { $0.capturesPoint(point) }) {
            return hit
        }
        // 여기 도달하는 캔버스 안의 점은 y == 마지막 captureRect.maxY(= totalHeight) 하나뿐이다.
        // 아래쪽에 이어받을 절이 없으므로 마지막 절에 닫힌 구간으로 귀속시킨다.
        // 반개구간 스캔이 실패한 뒤에만 동작하므로 겹침이 새로 생기지 않는다.
        guard let last = regions.last,
              point.y == last.captureRect.maxY,
              point.x >= last.captureRect.minX,
              point.x <= last.captureRect.maxX else {
            return nil
        }
        return last
    }

    /// 캔버스 좌표 한 점을 소유하는 절 번호.
    /// - Parameter point: 캔버스 좌표.
    /// - Returns: 절 번호. 캔버스 밖이면 nil.
    func verse(containing point: CGPoint) -> Int? {
        region(containing: point)?.verse
    }
}
