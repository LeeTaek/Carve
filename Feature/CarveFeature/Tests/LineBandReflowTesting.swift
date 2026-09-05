//
//  LineBandReflowTesting.swift
//  CarveFeatureTest
//
//  Phase 0B — line band reflow (§9)
//  단일 Canvas 설계(docs/single-canvas-design.md) §9-2 / §9-3 / §9-3-1 / §9-4 의 순수 로직을 UI 없이 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

// MARK: - 공용 헬퍼

/// reflow 테스트가 공유하는 레이아웃·기하 헬퍼.
enum ReflowTestSupport {
    static let chapter = BibleChapter(title: .genesis, chapter: 1)
    static let signature = "cl1-reflow-test"

    static func setting(lineSpace: CGFloat) -> SentenceSetting {
        SentenceSetting(
            lineSpace: lineSpace,
            fontSize: 20,
            traking: 1,
            baseLineHeight: 20,
            textHeight: .zero,
            fontFamily: .gothic,
            lineCount: 3
        )
    }

    /// 절 하나짜리 레이아웃과 그 절 영역.
    ///
    /// `topInset` 을 0이 아닌 값으로 두면 `writingRect.minY != 0` 이 되어
    /// "절 원점" 과 "첫 밑줄" 을 혼동한 구현이 드러난다.
    static func singleVerse(
        textLineCount: Int,
        savedBandCount: Int? = nil,
        measuredAnchors: [CGFloat]? = nil,
        writingWidth: CGFloat = 320,
        lineSpace: CGFloat = 30,
        topInset: CGFloat = 240
    ) -> (layout: ChapterLayout, region: VerseCanvasRegion) {
        let layout = ChapterLayoutBuilder().build(
            chapter: chapter,
            writingWidth: writingWidth,
            setting: setting(lineSpace: lineSpace),
            isLeftHanded: false,
            verses: [
                VerseLayoutInput(
                    verse: 1,
                    textLineCount: textLineCount,
                    savedBandCount: savedBandCount,
                    measuredUnderlineAnchors: measuredAnchors
                )
            ],
            metrics: ChapterLayoutMetrics(topInset: topInset)
        )
        return (layout, layout.regions[0])
    }

    /// 저장 좌표계(첫 밑줄 원점)의 직선 획.
    static func stroke(from start: CGPoint, to end: CGPoint, seed: UInt32) -> PKStroke {
        OwnershipTestSupport.stroke(from: start, to: end, seed: seed, creationTime: TimeInterval(seed) * 1_000)
    }

    /// 모든 control point 를 캔버스 좌표로 편다.
    static func canvasPoints(_ drawing: PKDrawing) -> [CGPoint] {
        drawing.strokes.flatMap { stroke in
            stroke.path.map { $0.location.applying(stroke.transform) }
        }
    }

    /// 획별 첫 control point(= §7-1 소유권 앵커)의 캔버스 좌표.
    static func canvasAnchors(_ drawing: PKDrawing) -> [CGPoint] {
        drawing.strokes.compactMap { stroke in
            stroke.path.first.map { $0.location.applying(stroke.transform) }
        }
    }

    /// control point 만으로 만든 경계 사각형. 잉크 두께가 섞이지 않아 종횡비 비교에 적합하다.
    static func canvasBounds(_ drawing: PKDrawing) -> CGRect {
        let points = canvasPoints(drawing)
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    static func identityKeys(_ drawing: PKDrawing) -> Set<StrokeIdentityKey> {
        Set(drawing.strokes.map { StrokeIdentityKey(stroke: $0) })
    }

    static func translated(_ points: [CGPoint], by offset: CGPoint) -> [CGPoint] {
        points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    /// 두 점열의 최대 편차. 개수가 다르면 무한대.
    static func maxDeviation(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> CGFloat {
        guard lhs.count == rhs.count else { return .infinity }
        return zip(lhs, rhs).reduce(0) { result, pair in
            max(result, max(abs(pair.0.x - pair.1.x), abs(pair.0.y - pair.1.y)))
        }
    }

    /// 저장 좌표계(첫 밑줄 원점) 기준 3줄짜리 필사.
    /// band 0 은 첫 밑줄 **위**(음수 y)에 있는 것이 정상이다.
    static func threeBandDrawing() -> PKDrawing {
        PKDrawing(strokes: [
            stroke(from: CGPoint(x: 10, y: -20), to: CGPoint(x: 60, y: -5), seed: 1),
            stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 25), seed: 2),
            stroke(from: CGPoint(x: 10, y: 40), to: CGPoint(x: 60, y: 55), seed: 3)
        ])
    }

    /// 3줄짜리 저장 metadata. 밑줄은 저장 좌표계에서 `[0, 30, 60]`.
    static func threeBandMetadata(baseWidth: CGFloat = 320) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: baseWidth,
            baseWritingHeight: 90,
            baseUnderlineAnchors: [0, 30, 60],
            layoutSignature: signature
        )
    }
}

// MARK: - §9-2 기본 동작

@Suite("Phase 0B — §9-2 line band reflow")
struct LineBandReflowTesting {
    private let reflow = LineBandReflow()

    @Test("같은 레이아웃이면 첫 밑줄로의 평행이동만 남는다 — 형태 무변환")
    func sameLayoutIsIdentityApartFromVerseTranslation() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let expected = ReflowTestSupport.translated(
            ReflowTestSupport.canvasPoints(stored),
            by: region.storageOrigin
        )
        #expect(result.outcome == .reflowed)
        #expect(ReflowTestSupport.maxDeviation(ReflowTestSupport.canvasPoints(result.displayDrawing), expected) < 0.001)
        #expect(result.displayDrawing.strokes.count == 3)
    }

    @Test("폭이 줄면 종횡비를 유지한 채 uniform 축소된다")
    func shrinksUniformlyWhenWidthDecreases() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3, writingWidth: 160)
        // band 1 한 줄만 담아 경계 사각형이 한 band 안에 머물게 한다.
        let stored = PKDrawing(strokes: [
            ReflowTestSupport.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 25), seed: 2)
        ])

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let before = ReflowTestSupport.canvasBounds(stored)
        let after = ReflowTestSupport.canvasBounds(result.displayDrawing)
        #expect(LineBandReflow.uniformScale(baseWidth: 320, currentWidth: 160) == 0.5)
        #expect(abs(after.width - before.width * 0.5) < 0.001)
        #expect(abs(after.height - before.height * 0.5) < 0.001)
        // 종횡비 보존
        #expect(abs(after.width / after.height - before.width / before.height) < 0.001)
    }

    @Test("폭이 늘어도 확대하지 않는다 — 크기 불변")
    func doesNotEnlargeWhenWidthIncreases() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3, writingWidth: 640)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let before = ReflowTestSupport.canvasBounds(stored)
        let after = ReflowTestSupport.canvasBounds(result.displayDrawing)
        #expect(LineBandReflow.uniformScale(baseWidth: 320, currentWidth: 640) == 1)
        #expect(abs(after.width - before.width) < 0.001)
        #expect(abs(after.height - before.height) < 0.001)
    }

    @Test("scale 기준값이 0 이하면 판단 근거가 없으므로 무변환(1)이다")
    func scaleFallsBackToOneWithoutUsableWidths() {
        #expect(LineBandReflow.uniformScale(baseWidth: 0, currentWidth: 160) == 1)
        #expect(LineBandReflow.uniformScale(baseWidth: 320, currentWidth: 0) == 1)
        #expect(LineBandReflow.uniformScale(baseWidth: -10, currentWidth: 160) == 1)
    }

    // MARK: - §9-3 줄 수 변화

    @Test("줄 수가 늘면 기존 획은 같은 index 밑줄에 정렬되고 남는 밑줄은 빈 줄이 된다")
    func extraUnderlinesStayEmptyWhenLineCountGrows() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 4)
        let stored = PKDrawing(strokes: [
            ReflowTestSupport.stroke(from: CGPoint(x: 10, y: -20), to: CGPoint(x: 60, y: -5), seed: 1),
            ReflowTestSupport.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 25), seed: 2)
        ])
        let metadata = DrawingLayoutMetadata(
            baseWritingWidth: 320,
            baseWritingHeight: 60,
            baseUnderlineAnchors: [0, 30],
            layoutSignature: ReflowTestSupport.signature
        )

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata),
            into: region
        )

        let canvasAnchors = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )
        #expect(region.underlineAnchors.count == 4)
        #expect(result.outcome == .reflowed)

        // 각 획이 저장 당시 밑줄로부터 갖던 offset 을 같은 index 의 현재 밑줄에 대해 그대로 갖는다.
        let anchors = ReflowTestSupport.canvasAnchors(result.displayDrawing)
        #expect(abs(anchors[0].y - (canvasAnchors[0] - 20)) < 0.001)
        #expect(abs(anchors[1].y - (canvasAnchors[1] - 20)) < 0.001)
        // 밑줄 2·3 구간에는 아무 잉크도 놓이지 않는다 (빈 줄).
        #expect(ReflowTestSupport.canvasBounds(result.displayDrawing).maxY < canvasAnchors[2])
    }

    @Test("줄 수가 줄면 초과 band 는 마지막 간격 연장으로 놓이고 §6-3 여유 안에 들어간다")
    func overflowBandsExtendTheLastGapWithinReservedHeight() {
        // §6-3 Pass 2 — 저장 band 3 / 현재 텍스트 2줄 → writingRect 에 한 줄치 여유가 확보된다.
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 2, savedBandCount: 3)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let canvasAnchors = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )
        let lastGap = canvasAnchors[1] - canvasAnchors[0]
        let virtualThirdAnchor = canvasAnchors[1] + lastGap

        #expect(result.outcome == .reflowed)
        #expect(region.underlineAnchors.count == 2)
        #expect(region.writingRect.height == 90)      // 2줄 × 30 + 여유 30

        // band 2 획은 "마지막 간격을 한 번 더 연장한" 가상 밑줄 기준으로 놓인다.
        let anchors = ReflowTestSupport.canvasAnchors(result.displayDrawing)
        #expect(abs(anchors[2].y - (virtualThirdAnchor - 20)) < 0.001)
        // 확보된 여유 안에 들어간다 — writingRect 밖으로 새지 않는다.
        #expect(ReflowTestSupport.canvasBounds(result.displayDrawing).maxY <= region.writingRect.maxY)
    }

    // MARK: - §9-3 legacy

    @Test("metadata 가 없으면 좌표를 전혀 건드리지 않는다 (legacy 무변환)")
    func legacyRowIsPassedThroughUntouched() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: nil),
            into: region
        )

        #expect(result.outcome == .legacyPassthrough)
        #expect(result.isLayoutMismatch == false)
        #expect(
            ReflowTestSupport.maxDeviation(
                ReflowTestSupport.canvasPoints(result.displayDrawing),
                ReflowTestSupport.canvasPoints(stored)
            ) == 0
        )
    }

    // MARK: - band 판정 기준

    @Test("band 는 §7-1 과 같은 앵커(첫 control point)로 정한다 — renderBounds 가 아니다")
    func bandIsDecidedByFirstControlPointNotRenderBounds() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3)
        // band 1 에서 시작해 위로 크게 올라가는 획. renderBounds.minY 는 band 0 에 걸린다.
        let stored = PKDrawing(strokes: [
            ReflowTestSupport.stroke(from: CGPoint(x: 10, y: 28), to: CGPoint(x: 60, y: -25), seed: 5)
        ])

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let canvasAnchors = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )
        // band 1(밑줄 index 1) 기준으로 놓여야 한다. band 0 이었다면 30pt 위에 놓인다.
        let anchor = ReflowTestSupport.canvasAnchors(result.displayDrawing)[0]
        #expect(abs(anchor.y - (canvasAnchors[1] - 2)) < 0.001)
    }

    @Test("마지막 밑줄보다 아래에서 시작한 획은 마지막 band 로 클램프된다")
    func strokesBelowLastUnderlineClampToLastBand() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3)
        let stored = PKDrawing(strokes: [
            ReflowTestSupport.stroke(from: CGPoint(x: 10, y: 75), to: CGPoint(x: 60, y: 80), seed: 6)
        ])

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let canvasAnchors = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )
        // base[2] == 60 이므로 저장 offset +15 가 마지막 밑줄 기준으로 그대로 유지된다.
        let anchor = ReflowTestSupport.canvasAnchors(result.displayDrawing)[0]
        #expect(abs(anchor.y - (canvasAnchors[2] + 15)) < 0.001)
    }
}

// MARK: - §9-3-1 매핑 실패 / §9-4 비파괴 / 장 단위

@Suite("Phase 0B — §9-3-1 매핑 실패와 §9-4 비파괴")
struct LineBandReflowMismatchTesting {
    private let reflow = LineBandReflow()

    @Test("현재 밑줄이 하나도 없으면 첫 밑줄 기준으로 통째 보존하고 mismatch 로 표시한다")
    func mismatchWhenCurrentLayoutHasNoUnderline() {
        // 텍스트 줄이 0인데 저장 band 는 3 — 옮겨 앉을 밑줄이 없다.
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 0, savedBandCount: 3)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        #expect(region.underlineAnchors.isEmpty)
        #expect(result.isLayoutMismatch)
        // §5 의 `?? 0` 규칙에 따라 첫 밑줄 자리는 writingRect 상단이다. 상대 배치는 그대로다.
        let expected = ReflowTestSupport.translated(
            ReflowTestSupport.canvasPoints(stored),
            by: region.storageOrigin
        )
        #expect(ReflowTestSupport.maxDeviation(ReflowTestSupport.canvasPoints(result.displayDrawing), expected) < 0.001)
    }

    @Test("저장 band 가 하나도 없으면 mismatch 로 처리한다")
    func mismatchWhenMetadataHasNoBand() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3)
        let metadata = DrawingLayoutMetadata(
            baseWritingWidth: 320,
            baseWritingHeight: 0,
            baseUnderlineAnchors: [],
            layoutSignature: ReflowTestSupport.signature
        )

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: ReflowTestSupport.threeBandDrawing(), metadata: metadata),
            into: region
        )

        #expect(result.isLayoutMismatch)
        #expect(metadata.savedBandCount == 0)
    }

    @Test("줄 수가 줄었는데 마지막 간격을 잴 수 없으면 한 줄에 겹쳐 쌓지 않고 mismatch 로 처리한다")
    func mismatchWhenLastGapCannotBeMeasured() {
        // 밑줄이 하나뿐이고 그 밑줄이 writingRect 상단과 같은 자리 → 연장할 간격이 0이다.
        let (_, region) = ReflowTestSupport.singleVerse(
            textLineCount: 1,
            savedBandCount: 3,
            measuredAnchors: [0]
        )

        let result = reflow.reflow(
            LineBandReflow.Input(
                verse: 1,
                storedDrawing: ReflowTestSupport.threeBandDrawing(),
                metadata: ReflowTestSupport.threeBandMetadata()
            ),
            into: region
        )

        #expect(region.underlineAnchors == [0])
        #expect(result.isLayoutMismatch)
    }

    @Test("mismatch 여도 좁아진 폭에 맞춰 축소는 적용된다")
    func mismatchStillAppliesWidthScale() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 0, savedBandCount: 3, writingWidth: 160)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        let before = ReflowTestSupport.canvasBounds(stored)
        let after = ReflowTestSupport.canvasBounds(result.displayDrawing)
        #expect(result.isLayoutMismatch)
        #expect(abs(after.width - before.width * 0.5) < 0.001)
        #expect(abs(after.height - before.height * 0.5) < 0.001)
    }

    // MARK: - ★ 두 기준점 혼동 회귀 (§5 vs §10-1)

    @Test("첫 밑줄 offset 이 0이 아니어도 같은 설정 왕복은 항등이다 — 기준점 혼동 회귀")
    func roundTripIsIdentityWhenFirstUnderlineOffsetIsNonZero() {
        // 첫 밑줄이 writingRect 상단에서 22pt 아래. 두 기준을 섞으면 정확히 22pt 어긋난다.
        let (layout, region) = ReflowTestSupport.singleVerse(
            textLineCount: 3,
            measuredAnchors: [22, 52, 82],
            topInset: 240
        )
        // 저장 metadata 는 반드시 이 레이아웃에서 유도한다 — 유일한 변환 지점.
        let metadata = layout.drawingLayoutMetadata(verse: 1)
        let stored = ReflowTestSupport.threeBandDrawing()

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata),
            into: region
        )

        #expect(metadata?.baseUnderlineAnchors == [0, 30, 60])
        #expect(region.underlineAnchors == [22, 52, 82])
        #expect(region.storageOrigin.y == 262)          // 240(writingRect 상단) + 22(첫 밑줄 offset)

        // 기준을 섞은 구현이라면 여기서 240 또는 284 만큼 밀린다.
        let expected = ReflowTestSupport.translated(
            ReflowTestSupport.canvasPoints(stored),
            by: CGPoint(x: 0, y: 262)
        )
        #expect(result.outcome == .reflowed)
        #expect(ReflowTestSupport.maxDeviation(ReflowTestSupport.canvasPoints(result.displayDrawing), expected) < 0.001)
    }

    @Test("metadata 에 §5 기준값이 잘못 기록돼 있어도 방어적 정규화로 같은 결과가 나온다")
    func wrongBasisInMetadataIsRecoveredByNormalization() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3, measuredAnchors: [22, 52, 82])
        let stored = ReflowTestSupport.threeBandDrawing()
        let correct = DrawingLayoutMetadata(region: region, layoutSignature: ReflowTestSupport.signature)
        // §5 기준값(첫 값 22)이 그대로 들어간 blob.
        let malformed = DrawingLayoutMetadata(
            baseWritingWidth: region.writingRect.width,
            baseWritingHeight: region.writingRect.height,
            baseUnderlineAnchors: [22, 52, 82],
            layoutSignature: ReflowTestSupport.signature
        )

        let fromCorrect = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: correct),
            into: region
        )
        let fromMalformed = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: malformed),
            into: region
        )

        #expect(
            ReflowTestSupport.maxDeviation(
                ReflowTestSupport.canvasPoints(fromCorrect.displayDrawing),
                ReflowTestSupport.canvasPoints(fromMalformed.displayDrawing)
            ) < 0.001
        )
    }

    // MARK: - §9-4 비파괴 (P10)

    @Test("reflow 는 입력 drawing 을 변경하지 않는다")
    func doesNotMutateInput() {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 3, writingWidth: 160)
        let stored = ReflowTestSupport.threeBandDrawing()
        let before = ReflowTestSupport.canvasPoints(stored)

        _ = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: ReflowTestSupport.threeBandMetadata()),
            into: region
        )

        #expect(ReflowTestSupport.maxDeviation(ReflowTestSupport.canvasPoints(stored), before) == 0)
    }

    // MARK: - 장 단위

    @Test("장 단위 reflow 는 절 순서를 보존하고 mismatch 절만 모은다")
    func chapterReflowCollectsMismatchVerses() {
        let layout = ChapterLayoutBuilder().build(
            chapter: ReflowTestSupport.chapter,
            writingWidth: 320,
            setting: ReflowTestSupport.setting(lineSpace: 30),
            isLeftHanded: false,
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 0, savedBandCount: 3)
            ]
        )
        let inputs = [
            LineBandReflow.Input(
                verse: 1,
                storedDrawing: ReflowTestSupport.threeBandDrawing(),
                metadata: ReflowTestSupport.threeBandMetadata()
            ),
            LineBandReflow.Input(
                verse: 2,
                storedDrawing: ReflowTestSupport.threeBandDrawing(),
                metadata: ReflowTestSupport.threeBandMetadata()
            ),
            LineBandReflow.Input(
                verse: 9,                              // 레이아웃에 없는 절
                storedDrawing: PKDrawing(strokes: [ReflowTestSupport.stroke(from: .zero, to: CGPoint(x: 5, y: 5), seed: 9)]),
                metadata: ReflowTestSupport.threeBandMetadata()
            )
        ]

        let result = reflow.reflow(inputs, into: layout)

        #expect(result.verses.map(\.verse) == [1, 2, 9])
        #expect(result.verses[0].outcome == .reflowed)
        #expect(result.layoutMismatchVerses == [2, 9])
        #expect(result.displayDrawing.strokes.count == 7)   // 3 + 3 + 1
    }

    @Test("legacy 절은 mismatch 로 세지 않는다")
    func legacyVerseIsNotCountedAsMismatch() {
        let layout = ChapterLayoutBuilder().build(
            chapter: ReflowTestSupport.chapter,
            writingWidth: 320,
            setting: ReflowTestSupport.setting(lineSpace: 30),
            isLeftHanded: false,
            verses: [VerseLayoutInput(verse: 1, textLineCount: 3)]
        )

        let result = reflow.reflow(
            [LineBandReflow.Input(verse: 1, storedDrawing: ReflowTestSupport.threeBandDrawing(), metadata: nil)],
            into: layout
        )

        #expect(result.verses[0].outcome == .legacyPassthrough)
        #expect(result.layoutMismatchVerses.isEmpty)
    }
}

// MARK: - 실사용 fixture 회귀 (§13 Phase 0B)

@Suite("Phase 0B — §9 reflow 실사용 fixture 회귀")
struct LineBandReflowFixtureTesting {
    private let reflow = LineBandReflow()

    /// fixture 는 절 로컬(좌상단 기준) 좌표다. 첫 밑줄이 절 상단에서 `lineSpace` 만큼
    /// 아래에 있다고 보고 **저장 좌표계(첫 밑줄 원점)** 로 옮긴다.
    private static let lineSpace: CGFloat = 45

    private func storedDrawing(_ sample: LegacyDrawingFixture.Sample) throws -> PKDrawing {
        try sample.drawing().transformed(using: CGAffineTransform(translationX: 0, y: -Self.lineSpace))
    }

    /// fixture 의 세로 범위를 덮는 5줄 metadata.
    private func metadata(baseWidth: CGFloat = 320) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: baseWidth,
            baseWritingHeight: Self.lineSpace * 5,
            baseUnderlineAnchors: (0..<5).map { CGFloat($0) * Self.lineSpace },
            layoutSignature: ReflowTestSupport.signature
        )
    }

    @Test("실사용 필사도 같은 레이아웃이면 첫 밑줄로의 평행이동만 남는다")
    func realHandwritingIsIdentityUnderSameLayout() throws {
        let stored = try storedDrawing(LegacyDrawingFixture.multiLine)
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 5, lineSpace: Self.lineSpace)

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata()),
            into: region
        )

        let expected = ReflowTestSupport.translated(
            ReflowTestSupport.canvasPoints(stored),
            by: region.storageOrigin
        )
        #expect(result.outcome == .reflowed)
        #expect(stored.strokes.count == LegacyDrawingFixture.multiLine.expectedStrokeCount)
        #expect(ReflowTestSupport.maxDeviation(ReflowTestSupport.canvasPoints(result.displayDrawing), expected) < 0.05)
    }

    @Test("실사용 필사는 폭이 줄면 가로로 정확히 그 비율만큼 줄어든다")
    func realHandwritingShrinksWithWidth() throws {
        let stored = try storedDrawing(LegacyDrawingFixture.multiLine)
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 5, writingWidth: 160, lineSpace: Self.lineSpace)

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata()),
            into: region
        )

        let before = ReflowTestSupport.canvasBounds(stored)
        let after = ReflowTestSupport.canvasBounds(result.displayDrawing)
        #expect(abs(after.width - before.width * 0.5) < 0.05)
        // 축소된 필사는 좁아진 필사 영역 안에 들어간다.
        #expect(after.minX >= region.writingRect.minX - 0.05)
        #expect(after.maxX <= region.writingRect.maxX + 0.05)
    }

    @Test("실사용 필사는 폭이 늘어도 커지지 않는다")
    func realHandwritingDoesNotGrowWithWidth() throws {
        let stored = try storedDrawing(LegacyDrawingFixture.wideLine)
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 5, writingWidth: 640, lineSpace: Self.lineSpace)

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata()),
            into: region
        )

        let before = ReflowTestSupport.canvasBounds(stored)
        let after = ReflowTestSupport.canvasBounds(result.displayDrawing)
        #expect(abs(after.width - before.width) < 0.05)
        #expect(abs(after.height - before.height) < 0.05)
    }

    @Test("reflow 는 획 수와 StrokeIdentityKey 를 보존한다 — 소유권이 살아남는다 (§7-3)")
    func preservesStrokeCountAndIdentityKeys() throws {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 5, writingWidth: 200, lineSpace: Self.lineSpace)

        for sample in LegacyDrawingFixture.all {
            let stored = try storedDrawing(sample)
            let result = reflow.reflow(
                LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata()),
                into: region
            )

            #expect(result.displayDrawing.strokes.count == sample.expectedStrokeCount)
            #expect(ReflowTestSupport.identityKeys(result.displayDrawing) == ReflowTestSupport.identityKeys(stored))
        }
    }

    @Test("metadata 가 없는 실사용 legacy blob 은 좌표가 그대로 유지된다")
    func realLegacyBlobIsUntouched() throws {
        let (_, region) = ReflowTestSupport.singleVerse(textLineCount: 5, writingWidth: 160, lineSpace: Self.lineSpace)

        for sample in LegacyDrawingFixture.all {
            let stored = try sample.drawing()
            let result = reflow.reflow(
                LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: nil),
                into: region
            )

            #expect(result.outcome == .legacyPassthrough)
            #expect(
                ReflowTestSupport.maxDeviation(
                    ReflowTestSupport.canvasPoints(result.displayDrawing),
                    ReflowTestSupport.canvasPoints(stored)
                ) == 0
            )
        }
    }

    @Test("실사용 필사도 줄 수가 줄면 확보된 여유 안에 들어간다 (§6-3)")
    func realHandwritingFitsReservedHeightWhenLineCountShrinks() throws {
        let stored = try storedDrawing(LegacyDrawingFixture.multiLine)
        // 저장 5줄 → 현재 3줄. §6-3 Pass 2 가 두 줄치 여유를 writingRect 에 확보한다.
        let (_, region) = ReflowTestSupport.singleVerse(
            textLineCount: 3,
            savedBandCount: 5,
            lineSpace: Self.lineSpace
        )

        let result = reflow.reflow(
            LineBandReflow.Input(verse: 1, storedDrawing: stored, metadata: metadata()),
            into: region
        )

        #expect(result.outcome == .reflowed)
        #expect(region.writingRect.height == Self.lineSpace * 5)
        #expect(ReflowTestSupport.canvasBounds(result.displayDrawing).maxY <= region.writingRect.maxY)
    }
}
