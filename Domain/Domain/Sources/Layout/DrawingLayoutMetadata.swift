//
//  DrawingLayoutMetadata.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Foundation

// MARK: - 밑줄 기준점 변환 (설계 §5 ↔ §10-1) ★

/// **밑줄 기준점은 두 종류다.** 그 사이를 오가는 변환을 이 타입 **한 곳에만** 둔다.
///
/// | 타입 | 필드 | 기준 |
/// |---|---|---|
/// | `VerseCanvasRegion` (설계 §5) | `underlineAnchors` | **`writingRect` 상단** 기준 상대값 |
/// | `DrawingLayoutMetadata` (설계 §10-1) | `baseUnderlineAnchors` | **첫 밑줄** 기준 상대값 (첫 값이 0) |
///
/// 저장된 stroke 의 좌표계는 `VerseCanvasRegion.storageOrigin`, 즉 **첫 밑줄**이 원점이다.
/// 따라서 `baseUnderlineAnchors` 는 저장 stroke 와 **같은 좌표 공간**의 값이고,
/// `underlineAnchors` 는 그렇지 않다.
///
/// > ⚠️ 두 기준을 섞으면 **첫 밑줄 offset 만큼 전체가 밀린다.** 증상이 "약간 어긋남" 이라
/// > 눈치채기 어렵다. reflow 는 두 기준을 모두 다루므로, 변환은 반드시 이 타입을 통해서만 한다.
public enum UnderlineAnchorBasis {
    /// **§5 기준 → §10-1 기준.** `writingRect` 상단 기준값을 첫 밑줄 기준값으로 옮긴다.
    ///
    /// 첫 값을 전부에서 빼는 것이 전부이므로 **멱등(idempotent)** 이다.
    /// 그래서 이 함수는 두 가지 용도를 겸한다.
    ///
    /// 1. `VerseCanvasRegion.underlineAnchors` → `DrawingLayoutMetadata.baseUnderlineAnchors` 변환.
    /// 2. 이미 §10-1 기준이어야 하는 값의 **방어적 재정규화** — 영속 blob 이 잘못된 기준으로
    ///    기록돼 있어도(첫 값 ≠ 0) 상대 간격은 살아 있으므로 이 함수를 한 번 더 적용하면 복구된다.
    ///
    /// - Parameter anchors: `writingRect` 상단 기준 밑줄 y (오름차순).
    /// - Returns: 첫 밑줄 기준 밑줄 y. 첫 값은 항상 0이다. 입력이 비면 빈 배열.
    public static func firstUnderlineRelative(writingRectRelative anchors: [CGFloat]) -> [CGFloat] {
        guard let first = anchors.first else { return [] }
        return anchors.map { $0 - first }
    }

    /// **§5 기준 → 캔버스 절대 y.**
    ///
    /// `VerseCanvasRegion.storageOrigin` 이 첫 밑줄 하나를 절대좌표로 올리는 것과 같은 계산을
    /// 전 밑줄로 확장한 것이다. 즉 `canvasAbsolute(...).first == region.storageOrigin.y` 다.
    /// - Parameters:
    ///   - anchors: `writingRect` 상단 기준 밑줄 y.
    ///   - writingRect: 해당 절의 `writingRect`.
    /// - Returns: 캔버스 절대 y.
    public static func canvasAbsolute(writingRectRelative anchors: [CGFloat], writingRect: CGRect) -> [CGFloat] {
        anchors.map { writingRect.minY + $0 }
    }
}

// MARK: - §10-1 DrawingLayoutMetadata

/// 저장 시점의 레이아웃을 재현하기 위한 metadata (설계 §10-1).
///
/// 스키마 V4 의 `BibleDrawing.layoutMetadataData` 에 Codable blob 으로 실릴 값이지만,
/// **이 타입 자체는 순수 DTO 다.** SwiftData 를 알지 못하며 영속 스키마도 여기서 정의하지 않는다
/// (스키마 추가는 Phase 1 의 일이다).
///
/// - Note: 좌표 형식의 단일 진실은 `BibleDrawing.drawingVersion` 이다(설계 §10-1).
///         그 값을 이 타입에 **중복해서 담지 않는다.** `metadataSchemaVersion` 은
///         "이 blob 자체의 인코딩 버전" 일 뿐 좌표 형식이 아니다.
public struct DrawingLayoutMetadata: Codable, Sendable, Equatable {
    /// 현재 코드가 기록하는 blob 스키마 버전.
    public static let currentSchemaVersion = 1

    /// 이 blob 자체의 스키마 버전. 좌표 형식(`drawingVersion`)과는 별개다.
    public let metadataSchemaVersion: Int
    /// 저장 시점의 필사 영역 폭. reflow 의 uniform scale 기준값이다(설계 §9-2).
    public let baseWritingWidth: CGFloat
    /// 저장 시점의 `writingRect` 높이. §6-3 여유 높이가 포함된 값이다.
    ///
    /// 현재 reflow 는 폭만으로 scale 을 정하므로(설계 §9-2) 이 값을 계산에 쓰지 않는다.
    /// 진단·후속 정책(예: 세로 여유 검증)을 위해 함께 영속화한다.
    public let baseWritingHeight: CGFloat
    /// **첫 밑줄 기준** 상대 y (첫 값은 0). 저장된 stroke 와 같은 좌표 공간이다.
    ///
    /// `VerseCanvasRegion.underlineAnchors`(= `writingRect` 상단 기준)와 **기준이 다르다.**
    /// 변환은 `UnderlineAnchorBasis` 를 통해서만 한다.
    public let baseUnderlineAnchors: [CGFloat]
    /// 저장 시점의 줄별 문자 범위 (설계 §9-3 "줄바꿈만 달라짐" 행의 입력).
    ///
    /// 측정 주체는 View 계층(`Text.Layout.Run.characterIndices`)이며 Phase 2 에서 채워진다.
    /// 값이 있어도 **현재 reflow 는 사용하지 않는다** — `LineBandReflow` 주석 참조.
    public let textLineRanges: [Range<Int>]?
    /// 저장 시점 레이아웃의 안정적 signature (설계 §6-5). `hashValue` 기반 값이 아니다.
    public let layoutSignature: String

    /// 구성요소를 직접 지정해 만든다. 영속 blob 디코딩과 테스트가 쓰는 경로다.
    ///
    /// - Important: `baseUnderlineAnchors` 는 **첫 밑줄 기준**이어야 한다.
    ///              레이아웃에서 유도할 때는 이 이니셜라이저 대신
    ///              `init(region:layoutSignature:textLineRanges:)` 를 써서 기준을 섞지 않도록 한다.
    /// - Parameters:
    ///   - metadataSchemaVersion: blob 스키마 버전.
    ///   - baseWritingWidth: 저장 시점 필사 영역 폭.
    ///   - baseWritingHeight: 저장 시점 `writingRect` 높이.
    ///   - baseUnderlineAnchors: 첫 밑줄 기준 밑줄 y.
    ///   - textLineRanges: 저장 시점 줄별 문자 범위.
    ///   - layoutSignature: 저장 시점 레이아웃 signature.
    public init(
        metadataSchemaVersion: Int = DrawingLayoutMetadata.currentSchemaVersion,
        baseWritingWidth: CGFloat,
        baseWritingHeight: CGFloat,
        baseUnderlineAnchors: [CGFloat],
        textLineRanges: [Range<Int>]? = nil,
        layoutSignature: String
    ) {
        self.metadataSchemaVersion = metadataSchemaVersion
        self.baseWritingWidth = baseWritingWidth
        self.baseWritingHeight = baseWritingHeight
        self.baseUnderlineAnchors = baseUnderlineAnchors
        self.textLineRanges = textLineRanges
        self.layoutSignature = layoutSignature
    }

    /// 현재 레이아웃의 절 영역에서 metadata 를 유도한다. **기준점 변환이 일어나는 지점이다.**
    ///
    /// `region.underlineAnchors` 는 `writingRect` 상단 기준이므로 그대로 담으면 안 되고,
    /// `UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative:)` 로 첫 밑줄 기준으로 옮긴다.
    /// - Parameters:
    ///   - region: 저장 시점 절 영역.
    ///   - layoutSignature: 저장 시점 레이아웃 signature.
    ///   - textLineRanges: 저장 시점 줄별 문자 범위. 측정값이 없으면 nil.
    ///   - metadataSchemaVersion: blob 스키마 버전.
    public init(
        region: VerseCanvasRegion,
        layoutSignature: String,
        textLineRanges: [Range<Int>]? = nil,
        metadataSchemaVersion: Int = DrawingLayoutMetadata.currentSchemaVersion
    ) {
        self.init(
            metadataSchemaVersion: metadataSchemaVersion,
            baseWritingWidth: region.writingRect.width,
            baseWritingHeight: region.writingRect.height,
            baseUnderlineAnchors: UnderlineAnchorBasis.firstUnderlineRelative(
                writingRectRelative: region.underlineAnchors
            ),
            textLineRanges: textLineRanges,
            layoutSignature: layoutSignature
        )
    }

    /// 방어적으로 재정규화한 `baseUnderlineAnchors`. 첫 값이 반드시 0이다.
    ///
    /// 올바르게 기록된 blob 이라면 `baseUnderlineAnchors` 와 같다. reflow 는 이 값을 쓴다 —
    /// 잘못된 기준으로 기록된 blob 이 섞여 들어와도 첫 밑줄 offset 만큼 밀리지 않게 하기 위함이다.
    public var normalizedBaseUnderlineAnchors: [CGFloat] {
        UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative: baseUnderlineAnchors)
    }

    /// 저장 시점의 band(줄) 수. 설계 §6-3 Pass 2 의 `N_saved` 다.
    public var savedBandCount: Int {
        baseUnderlineAnchors.count
    }
}

// MARK: - ChapterLayout 연동

public extension ChapterLayout {
    /// 이 레이아웃에서 해당 절을 저장할 때 함께 기록할 metadata.
    ///
    /// 저장 경로(설계 §8-2 의 `VerseDrawingMutation`)가 metadata 를 만들 때 쓰는 단일 진입점이다.
    /// `signature` 를 레이아웃에서 직접 가져오므로 저장 시점과 어긋날 수 없다.
    /// - Parameters:
    ///   - verse: 절 번호.
    ///   - textLineRanges: 저장 시점 줄별 문자 범위. 측정값이 없으면 nil.
    /// - Returns: metadata. 해당 절이 레이아웃에 없으면 nil.
    func drawingLayoutMetadata(verse: Int, textLineRanges: [Range<Int>]? = nil) -> DrawingLayoutMetadata? {
        guard let region = region(verse: verse) else { return nil }
        return DrawingLayoutMetadata(
            region: region,
            layoutSignature: signature,
            textLineRanges: textLineRanges
        )
    }
}
