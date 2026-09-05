//
//  ChapterLayout.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Foundation

/// 절 하나의 캔버스 좌표 정보.
///
/// 좌표계는 **장 전체를 덮는 단일 캔버스**이며 원점은 캔버스 좌상단 `(0, 0)`이다.
/// 캔버스의 폭은 필사 영역(writing column)의 폭과 같으므로 `writingRect.minX`는 항상 0이다.
public struct VerseCanvasRegion: Equatable, Sendable {
    /// 절 번호.
    public let verse: Int
    /// 밑줄이 실제 표시되는 영역.
    ///
    /// - Note: 저장된 band 수가 현재 텍스트 줄 수보다 많으면(설계 §6-3 Pass 2)
    ///         그만큼의 여유 높이가 이 사각형 **하단에 포함**된다.
    ///         즉 `height >= underlineAnchors.count * lineSpace` 이며,
    ///         초과 band는 마지막 밑줄 아래의 여유 공간에 놓인다(설계 §9-3).
    ///         여유 높이를 절 사이 gap으로 두지 않고 `writingRect`에 포함시키는 이유는,
    ///         `captureRect`가 midpoint로 갈라질 때 그 공간의 절반이 다음 절 소유로 넘어가는 것을 막기 위함이다.
    public let writingRect: CGRect
    /// 획 소유권을 판정하는 영역 (인접 절과의 midpoint로 분할).
    public let captureRect: CGRect
    /// 밑줄 y 좌표 (`writingRect` 기준 **상대값**. 절대좌표가 아니다).
    public let underlineAnchors: [CGFloat]

    /// 저장 origin = (writingRect.minX, 첫 밑줄 y).
    public var storageOrigin: CGPoint {
        CGPoint(x: writingRect.minX,
                y: writingRect.minY + (underlineAnchors.first ?? 0))
    }

    public init(
        verse: Int,
        writingRect: CGRect,
        captureRect: CGRect,
        underlineAnchors: [CGFloat]
    ) {
        self.verse = verse
        self.writingRect = writingRect
        self.captureRect = captureRect
        self.underlineAnchors = underlineAnchors
    }
}

/// 장 전체 레이아웃 — 단일 좌표계의 유일한 진실 공급원.
public struct ChapterLayout: Equatable, Sendable {
    /// 이 레이아웃이 속한 장.
    public let chapter: BibleChapter
    /// 필사 영역의 폭. 캔버스 폭과 같다.
    public let writingWidth: CGFloat
    /// 캔버스 전체 높이.
    public let totalHeight: CGFloat
    /// 절 순서대로 정렬된 절별 좌표 정보.
    public let regions: [VerseCanvasRegion]
    /// 설계 §6-5의 안정적 signature. 프로세스 간 재현되는 값이며 `hashValue` 기반이 아니다.
    public let signature: String

    public init(
        chapter: BibleChapter,
        writingWidth: CGFloat,
        totalHeight: CGFloat,
        regions: [VerseCanvasRegion],
        signature: String
    ) {
        self.chapter = chapter
        self.writingWidth = writingWidth
        self.totalHeight = totalHeight
        self.regions = regions
        self.signature = signature
    }

    /// 절 번호로 영역을 조회.
    /// - Parameter verse: 절 번호.
    /// - Returns: 해당 절의 영역. 없으면 nil.
    public func region(verse: Int) -> VerseCanvasRegion? {
        regions.first { $0.verse == verse }
    }

    /// 설계 §6-2의 입력/합성 게이트.
    ///
    /// 이 조건을 모두 만족하기 전에는 합성·입력·저장을 금지한다.
    /// 부분 레이아웃을 정상 상태처럼 취급하지 않기 위한 단일 판정 지점이다.
    /// - Parameter expectedVerseCount: 본문 fetch로 확정된 절 개수.
    /// - Returns: 게이트 통과 여부.
    public func satisfiesCompositionGate(expectedVerseCount: Int) -> Bool {
        regions.count == expectedVerseCount
            && totalHeight > 0
            && writingWidth > 0
    }
}
