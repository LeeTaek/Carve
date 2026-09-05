//
//  ChapterLayoutBuilder.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Foundation

/// 절 하나에 대한 레이아웃 입력.
///
/// **측정 결과를 받는 값이지 측정을 요청하는 값이 아니다.**
/// 텍스트 줄 수와 밑줄 위치는 View 계층(`Text.LayoutKey`)이 실측해 채워 넣는다.
public struct VerseLayoutInput: Equatable, Sendable {
    /// 절 번호.
    public let verse: Int
    /// 현재 설정·폭에서 실측된 텍스트 줄 수 (설계 §6-3의 `N_now`).
    public let textLineCount: Int
    /// 저장된 필사가 차지하던 band(줄) 수 (설계 §6-3의 `N_saved`).
    /// 저장 데이터가 없거나 metadata가 없는 legacy 행이면 nil.
    public let savedBandCount: Int?
    /// View 계층이 실측한 밑줄 y. **`writingRect` 기준 상대값**으로 이미 변환된 값이어야 한다.
    ///
    /// nil이거나 개수가 `textLineCount`와 다르면 빌더가 `lineSpace` 기반 band 하단으로 근사한다.
    /// 이 값은 `baseUnderlineAnchors`로 영속화되어 reflow의 기준이 되므로(설계 §9-3-2),
    /// 가능하면 실측값을 넣는 쪽이 좋다.
    /// `topPadding` 이 있으면 실측값도 그 여백을 **포함한** 값이어야 한다(둘 다 `writingRect` 상단 기준이므로).
    public let measuredUnderlineAnchors: [CGFloat]?
    /// 절 **위**에 놓이는 추가 여백 (Phase 2 — 실측 파이프라인에서 추가).
    ///
    /// `writingRect` 에 포함되지 **않는다.** 절 사이 gap 처럼 취급되어 `captureRect` 가 midpoint 로 나눠 갖는다.
    /// 장 중간 절에 붙는 소제목(예: 창세기 2:4 "에덴 동산")의 높이가 여기에 들어간다.
    /// 소제목은 절 본문이 아니므로 그 위에 그은 획을 특정 절의 필사로 강하게 귀속시킬 이유가 없다.
    public let leadingInset: CGFloat
    /// `writingRect` **안**에 포함되는 상단 여백 (Phase 2 — 실측 파이프라인에서 추가).
    ///
    /// 밑줄 anchor 는 이 값 아래에서 시작한다. 즉 근사 anchor 는 `topPadding + (index + 1) × lineSpace` 다.
    /// 현재 N-Canvas 구조에서 장의 첫 절이 갖는 상단 여백 25pt 가 여기에 해당한다 —
    /// 그 여백은 절의 캔버스 **안**에 있어서 legacy 절-로컬 좌표가 그만큼 아래에서 시작하므로,
    /// `writingRect` 밖으로 빼면 legacy 데이터가 25pt 위로 밀려 보인다.
    public let topPadding: CGFloat

    public init(
        verse: Int,
        textLineCount: Int,
        savedBandCount: Int? = nil,
        measuredUnderlineAnchors: [CGFloat]? = nil,
        leadingInset: CGFloat = 0,
        topPadding: CGFloat = 0
    ) {
        self.verse = verse
        self.textLineCount = textLineCount
        self.savedBandCount = savedBandCount
        self.measuredUnderlineAnchors = measuredUnderlineAnchors
        self.leadingInset = max(0, leadingInset)
        self.topPadding = max(0, topPadding)
    }
}

/// 절 배치에 쓰이는 여백 값.
public struct ChapterLayoutMetrics: Equatable, Sendable {
    /// 첫 절 위 여백.
    public let topInset: CGFloat
    /// 절과 절 사이 간격. 이 간격은 어느 절의 `writingRect`에도 속하지 않지만
    /// `captureRect`가 midpoint로 나눠 가지므로 소유권 구멍이 생기지 않는다.
    public let verseSpacing: CGFloat
    /// 마지막 절 아래 여백.
    public let bottomInset: CGFloat

    public static let zero = ChapterLayoutMetrics()

    public init(
        topInset: CGFloat = 0,
        verseSpacing: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) {
        self.topInset = topInset
        self.verseSpacing = verseSpacing
        self.bottomInset = bottomInset
    }
}

/// 장 전체의 단일 캔버스 좌표를 계산하는 순수 함수 (설계 §6).
///
/// **이 타입은 텍스트를 측정하지 않는다.** 측정은 View 계층(`Text.LayoutKey`)의 책임이고,
/// 빌더는 이미 측정된 줄 수·밑줄 위치를 입력으로 받아 좌표 **영역**만 계산한다(설계 §4의 책임 분리).
/// 따라서 UIKit/SwiftUI 렌더링 없이 단위 테스트로 전부 검증할 수 있다.
public struct ChapterLayoutBuilder: Sendable {
    public init() { }

    /// 절별 좌표와 signature를 계산한다.
    /// - Parameters:
    ///   - chapter: 대상 장.
    ///   - writingWidth: 필사 영역 폭. 캔버스 폭과 같다.
    ///   - setting: 본문 렌더링 설정. `lineSpace`가 band 높이의 단일 기준이다.
    ///   - isLeftHanded: 왼손 모드 여부. signature 구성요소(layoutDirection)다.
    ///   - verses: 절 순서대로 정렬된 측정 결과. 결과 `regions`는 이 순서를 그대로 보존한다.
    ///   - metrics: 배치 여백.
    /// - Returns: 계산된 장 레이아웃.
    public func build(
        chapter: BibleChapter,
        writingWidth: CGFloat,
        setting: SentenceSetting,
        isLeftHanded: Bool,
        verses: [VerseLayoutInput],
        metrics: ChapterLayoutMetrics = .zero
    ) -> ChapterLayout {
        let lineSpace = max(0, setting.lineSpace)
        let width = max(0, writingWidth)

        // ── Pass 1 ──────────────────────────────────────────────────────────
        // 텍스트 줄 수만으로 각 절의 밑줄 개수와 높이를 구한다. 아직 좌표를 만들지 않는다.
        // `topPadding` 은 `writingRect` 안의 여백이므로 텍스트 높이에 더해지고 근사 anchor 도 그만큼 내려간다.
        var lineCounts: [Int] = []
        var textHeights: [CGFloat] = []
        var anchors: [[CGFloat]] = []
        for input in verses {
            let lineCount = max(0, input.textLineCount)
            lineCounts.append(lineCount)
            textHeights.append(input.topPadding + CGFloat(lineCount) * lineSpace)
            anchors.append(Self.underlineAnchors(for: input, lineCount: lineCount, lineSpace: lineSpace))
        }

        // ── Pass 2 ──────────────────────────────────────────────────────────
        // 저장된 band 수(N_saved)와 현재 밑줄 수(N_now)를 **개수로만** 비교해 여유 높이를 더한다.
        //   N_saved > N_now  →  extraHeight = (N_saved - N_now) × lineSpace
        // Pass 2는 좌표를 전혀 참조하지 않는다. 이것이 "reflow 결과 → 레이아웃 → reflow" 순환을
        // 만들지 않는 근거다(설계 §6-3). 따라서 이 단계에 좌표 계산을 추가하면 안 된다.
        var effectiveHeights: [CGFloat] = []
        for (index, input) in verses.enumerated() {
            let savedBandCount = max(0, input.savedBandCount ?? 0)
            let extraBands = max(0, savedBandCount - lineCounts[index])
            effectiveHeights.append(textHeights[index] + CGFloat(extraBands) * lineSpace)
        }

        // ── 배치 ────────────────────────────────────────────────────────────
        // Pass 2로 확정된 높이를 위에서부터 쌓는다.
        // `leadingInset` 은 `writingRect` 밖의 여백이라 절 사이 gap 처럼 cursor 만 밀고 rect 에는 들어가지 않는다.
        var writingRects: [CGRect] = []
        var cursorY = metrics.topInset
        for (index, height) in effectiveHeights.enumerated() {
            if index > 0 {
                cursorY += metrics.verseSpacing
            }
            cursorY += verses[index].leadingInset
            writingRects.append(CGRect(x: 0, y: cursorY, width: width, height: height))
            cursorY += height
        }
        let totalHeight = max(cursorY, cursorY + metrics.bottomInset)

        return ChapterLayout(
            chapter: chapter,
            writingWidth: width,
            totalHeight: totalHeight,
            regions: Self.makeRegions(
                verses: verses,
                writingRects: writingRects,
                anchors: anchors,
                width: width,
                totalHeight: totalHeight
            ),
            signature: ChapterLayoutSignature.make(
                setting: setting,
                writingWidth: width,
                isLeftHanded: isLeftHanded
            )
        )
    }

    /// `captureRect`까지 채운 절별 영역을 만든다.
    ///
    /// 경계는 인접 절 `writingRect`의 midpoint다. 첫 절 위쪽은 캔버스 상단(0),
    /// 마지막 절 아래쪽은 캔버스 하단(`totalHeight`)까지 확장한다(설계 §5).
    /// 인접 `captureRect`의 경계가 같은 값이므로 절 사이 gap이 어느 절에도 속하지 않는
    /// 구멍은 생기지 않고, 겹침도 생기지 않는다.
    private static func makeRegions(
        verses: [VerseLayoutInput],
        writingRects: [CGRect],
        anchors: [[CGFloat]],
        width: CGFloat,
        totalHeight: CGFloat
    ) -> [VerseCanvasRegion] {
        let lastIndex = writingRects.count - 1
        return writingRects.enumerated().map { index, rect in
            let topBoundary = index == 0
                ? 0
                : midpoint(writingRects[index - 1].maxY, rect.minY)
            let bottomBoundary = index == lastIndex
                ? totalHeight
                : midpoint(rect.maxY, writingRects[index + 1].minY)
            return VerseCanvasRegion(
                verse: verses[index].verse,
                writingRect: rect,
                captureRect: CGRect(
                    x: 0,
                    y: topBoundary,
                    width: width,
                    height: max(0, bottomBoundary - topBoundary)
                ),
                underlineAnchors: anchors[index]
            )
        }
    }

    /// 밑줄 anchor를 `writingRect` 기준 **상대값**으로 만든다. 절대좌표를 만들지 않는다(설계 §5).
    ///
    /// 실측값이 들어오면 그대로 쓰고, 없으면 band 하단(`topPadding + (index + 1) × lineSpace`)으로 근사한다.
    /// 근사값은 `UIFont` 메트릭을 쓰지 않으므로 빌더의 순수성이 유지된다.
    private static func underlineAnchors(
        for input: VerseLayoutInput,
        lineCount: Int,
        lineSpace: CGFloat
    ) -> [CGFloat] {
        if let measured = input.measuredUnderlineAnchors, measured.count == lineCount {
            return measured
        }
        return (0..<lineCount).map { input.topPadding + CGFloat($0 + 1) * lineSpace }
    }

    /// 두 y 좌표의 중간값.
    private static func midpoint(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        (lower + upper) / 2
    }
}
