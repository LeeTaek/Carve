//
//  DrawingLayoutMetadataTesting.swift
//  DomainTest
//
//  Phase 0B — 설계 §10-1 DrawingLayoutMetadata 와 §5 ↔ §10-1 밑줄 기준점 변환
//

import CoreGraphics
import Foundation
import Testing

@testable import Domain

struct DrawingLayoutMetadataTesting {

    private static let signature = "cl1-test"

    /// 첫 밑줄 offset 이 **0이 아닌** 절 영역. 두 기준을 섞으면 그 offset 만큼 밀린다.
    private func makeRegion(
        writingRectTop: CGFloat = 240,
        anchors: [CGFloat] = [22, 52, 82],
        width: CGFloat = 320,
        height: CGFloat = 90
    ) -> VerseCanvasRegion {
        VerseCanvasRegion(
            verse: 3,
            writingRect: CGRect(x: 0, y: writingRectTop, width: width, height: height),
            captureRect: CGRect(x: 0, y: writingRectTop - 10, width: width, height: height + 20),
            underlineAnchors: anchors
        )
    }

    // MARK: - §5 ↔ §10-1 기준점 변환 ★

    @Test("§5 writingRect 기준 anchor 는 §10-1 첫 밑줄 기준으로 변환되고 첫 값이 0이 된다")
    func convertsWritingRectRelativeAnchorsToFirstUnderlineRelative() {
        let converted = UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative: [22, 52, 82])

        #expect(converted == [0, 30, 60])
        #expect(converted.first == 0)
    }

    @Test("변환은 멱등이다 — 이미 첫 밑줄 기준인 값에 다시 적용해도 변하지 않는다")
    func firstUnderlineRelativeConversionIsIdempotent() {
        let once = UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative: [22, 52, 82])
        let twice = UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative: once)

        #expect(once == twice)
    }

    @Test("빈 anchor 는 빈 배열로 변환된다")
    func convertsEmptyAnchorsToEmptyArray() {
        #expect(UnderlineAnchorBasis.firstUnderlineRelative(writingRectRelative: []).isEmpty)
        #expect(UnderlineAnchorBasis.canvasAbsolute(writingRectRelative: [], writingRect: .zero).isEmpty)
    }

    @Test("캔버스 절대 변환의 첫 값은 §5 의 storageOrigin.y 와 같다")
    func canvasAbsoluteFirstAnchorMatchesStorageOrigin() {
        let region = makeRegion()
        let absolute = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )

        #expect(absolute == [262, 292, 322])
        #expect(absolute.first == region.storageOrigin.y)
    }

    // MARK: - metadata 생성

    @Test("region 에서 만든 metadata 는 첫 밑줄 기준 anchor 를 담는다")
    func metadataFromRegionUsesFirstUnderlineBasis() {
        let region = makeRegion()
        let metadata = DrawingLayoutMetadata(region: region, layoutSignature: Self.signature)

        // §5 의 [22, 52, 82] 를 그대로 담으면 안 된다. 그러면 reflow 가 22pt 밀린다.
        #expect(metadata.baseUnderlineAnchors == [0, 30, 60])
        #expect(metadata.baseWritingWidth == 320)
        #expect(metadata.baseWritingHeight == 90)
        #expect(metadata.layoutSignature == Self.signature)
        #expect(metadata.metadataSchemaVersion == DrawingLayoutMetadata.currentSchemaVersion)
        #expect(metadata.savedBandCount == 3)
        #expect(metadata.textLineRanges == nil)
    }

    @Test("잘못된 기준으로 기록된 anchor 는 방어적으로 재정규화된다")
    func normalizesAnchorsRecordedInTheWrongBasis() {
        // §5 기준값이 그대로 들어간 상황을 재현한다 (첫 값이 0이 아니다).
        let malformed = DrawingLayoutMetadata(
            baseWritingWidth: 320,
            baseWritingHeight: 90,
            baseUnderlineAnchors: [22, 52, 82],
            layoutSignature: Self.signature
        )

        #expect(malformed.normalizedBaseUnderlineAnchors == [0, 30, 60])

        let correct = DrawingLayoutMetadata(region: makeRegion(), layoutSignature: Self.signature)
        #expect(malformed.normalizedBaseUnderlineAnchors == correct.normalizedBaseUnderlineAnchors)
    }

    @Test("ChapterLayout 은 절 번호로 metadata 를 만들고 자기 signature 를 담는다")
    func chapterLayoutProducesMetadataForVerse() {
        let layout = ChapterLayoutBuilder().build(
            chapter: BibleChapter(title: .genesis, chapter: 1),
            writingWidth: 320,
            setting: SentenceSetting(
                lineSpace: 30,
                fontSize: 20,
                traking: 1,
                baseLineHeight: 20,
                textHeight: .zero,
                fontFamily: .gothic,
                lineCount: 3
            ),
            isLeftHanded: false,
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2),
                VerseLayoutInput(verse: 2, textLineCount: 3)
            ]
        )

        let metadata = layout.drawingLayoutMetadata(verse: 2)

        #expect(metadata?.layoutSignature == layout.signature)
        // 빌더 기본 anchor 는 (i + 1) × lineSpace = [30, 60, 90] → 첫 밑줄 기준 [0, 30, 60]
        #expect(metadata?.baseUnderlineAnchors == [0, 30, 60])
        #expect(metadata?.baseWritingWidth == 320)
        #expect(layout.drawingLayoutMetadata(verse: 99) == nil)
    }

    // MARK: - 영속화

    @Test("metadata 는 Codable 라운드트립에서 값이 보존된다")
    func survivesCodableRoundTrip() throws {
        let original = DrawingLayoutMetadata(
            baseWritingWidth: 320,
            baseWritingHeight: 120,
            baseUnderlineAnchors: [0, 30, 60, 90],
            textLineRanges: [0..<13, 13..<26, 26..<40, 40..<46],
            layoutSignature: Self.signature
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrawingLayoutMetadata.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.textLineRanges?.count == 4)
        #expect(decoded.textLineRanges?.first == 0..<13)
    }

    @Test("textLineRanges 가 nil 인 metadata 도 라운드트립된다")
    func survivesCodableRoundTripWithoutTextLineRanges() throws {
        let original = DrawingLayoutMetadata(region: makeRegion(), layoutSignature: Self.signature)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DrawingLayoutMetadata.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.textLineRanges == nil)
    }
}
