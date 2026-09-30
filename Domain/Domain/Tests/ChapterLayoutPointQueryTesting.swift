//
//  ChapterLayoutPointQueryTesting.swift
//  DomainTest
//
//  Created by Claude on 9/5/26.
//

import CoreGraphics
import Foundation
import Testing

@testable import Domain

/// 설계 §7-1 의 "첫 control point → `captureRect` 검색 → ownerVerse" 중
/// **검색 단계**를 검증한다. 경계 위의 점이 두 절에 동시에 속하거나 어느 절에도 속하지 않는 일이
/// 없어야 한다는 것이 이 파일의 핵심이다.
struct ChapterLayoutPointQueryTesting {
    private let builder = ChapterLayoutBuilder()
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func makeSetting(lineSpace: CGFloat = 30) -> SentenceSetting {
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

    /// 여백이 섞인 3절 레이아웃.
    ///
    /// writingRect  v1 (0,10,320,30) · v2 (0,52,320,60) · v3 (0,124,320,90)
    /// captureRect  v1 [0,46) · v2 [46,118) · v3 [118,234]
    private func makeLayout(
        writingWidth: CGFloat = 320,
        lineSpace: CGFloat = 30,
        metrics: ChapterLayoutMetrics = ChapterLayoutMetrics(topInset: 10, verseSpacing: 12, bottomInset: 20)
    ) -> ChapterLayout {
        builder.build(
            chapter: chapter,
            writingWidth: writingWidth,
            setting: makeSetting(lineSpace: lineSpace),
            isLeftHanded: false,
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 1),
                VerseLayoutInput(verse: 2, textLineCount: 2),
                VerseLayoutInput(verse: 3, textLineCount: 3)
            ],
            metrics: metrics
        )
    }

    // MARK: - captureRect 내부

    @Test("captureRect 내부의 점은 해당 절이 소유한다")
    func pointInsideCaptureRectResolvesToItsVerse() {
        let layout = makeLayout()

        for region in layout.regions {
            let center = CGPoint(x: region.captureRect.midX, y: region.captureRect.midY)
            #expect(layout.verse(containing: center) == region.verse)
            #expect(layout.region(containing: center)?.captureRect == region.captureRect)
        }
    }

    @Test("writingRect 안의 점도 같은 절이 소유한다 — captureRect 는 writingRect 를 포함한다")
    func pointInsideWritingRectResolvesToSameVerse() {
        let layout = makeLayout()

        for region in layout.regions {
            let inside = CGPoint(x: 5, y: region.writingRect.midY)
            #expect(layout.verse(containing: inside) == region.verse)
        }
    }

    // MARK: - 경계값 — 중복도 누락도 없어야 한다

    @Test("절 사이 경계 위의 점은 아래(다음) 절이 소유한다 — 반개구간 [minY, maxY)")
    func boundaryPointBelongsToLowerVerse() {
        let layout = makeLayout()

        // v1/v2 경계 46, v2/v3 경계 118.
        #expect(layout.regions[0].captureRect.maxY == 46)
        #expect(layout.regions[1].captureRect.minY == 46)
        #expect(layout.verse(containing: CGPoint(x: 10, y: 46)) == 2)
        #expect(layout.verse(containing: CGPoint(x: 10, y: 118)) == 3)

        // 경계 바로 위는 여전히 윗절.
        #expect(layout.verse(containing: CGPoint(x: 10, y: 45.999)) == 1)
        #expect(layout.verse(containing: CGPoint(x: 10, y: 117.999)) == 2)
    }

    @Test("캔버스 세로 전 구간에서 소유 절이 정확히 하나다 — 중복도 누락도 없다")
    func everyPointInCanvasHasExactlyOneOwner() {
        let layout = makeLayout()
        let bottom = layout.totalHeight

        // 0.5pt 간격 전수 스캔 + 경계값 정확히.
        var samples: [CGFloat] = stride(from: CGFloat(0), through: bottom, by: 0.5).map { $0 }
        for region in layout.regions {
            samples.append(region.captureRect.minY)
            samples.append(region.captureRect.maxY)
        }

        for sampleY in samples where sampleY <= bottom {
            let point = CGPoint(x: 10, y: sampleY)
            let owners = layout.regions.filter { $0.capturesPoint(point) }

            if sampleY == bottom {
                // 캔버스 하단 경계는 반개구간 어디에도 속하지 않는다. 레이아웃이 마지막 절에 닫아 준다.
                #expect(owners.isEmpty)
                #expect(layout.verse(containing: point) == layout.regions.last?.verse)
            } else {
                #expect(owners.count == 1, "y=\(sampleY) 의 소유 절이 \(owners.count) 개다")
                #expect(layout.verse(containing: point) == owners.first?.verse)
            }
        }
    }

    @Test("캔버스 상단(y=0)은 첫 절, 하단(y=totalHeight)은 마지막 절이 소유한다")
    func canvasEdgesAreOwned() {
        let layout = makeLayout()

        #expect(layout.verse(containing: CGPoint(x: 0, y: 0)) == 1)
        #expect(layout.verse(containing: CGPoint(x: 10, y: layout.totalHeight)) == 3)
    }

    @Test("가로는 닫힌 구간이라 오른쪽 끝 점도 소유자가 있다")
    func rightEdgeIsOwned() {
        let layout = makeLayout()

        #expect(layout.verse(containing: CGPoint(x: layout.writingWidth, y: 60)) == 2)
        #expect(layout.verse(containing: CGPoint(x: layout.writingWidth, y: layout.totalHeight)) == 3)
    }

    @Test("절 사이 간격(verseSpacing)도 captureRect 가 흡수해 소유권 구멍이 없다")
    func verseSpacingGapIsAbsorbed() {
        let layout = makeLayout()
        let firstGap = layout.regions[0].writingRect.maxY...layout.regions[1].writingRect.minY

        for sampleY in stride(from: firstGap.lowerBound, through: firstGap.upperBound, by: 0.25) {
            #expect(layout.verse(containing: CGPoint(x: 10, y: sampleY)) != nil)
        }
    }

    // MARK: - 캔버스 밖

    @Test("캔버스 밖의 점은 소유자가 없다")
    func pointOutsideCanvasHasNoOwner() {
        let layout = makeLayout()

        #expect(layout.verse(containing: CGPoint(x: 10, y: -0.001)) == nil)
        #expect(layout.verse(containing: CGPoint(x: 10, y: layout.totalHeight + 0.001)) == nil)
        #expect(layout.verse(containing: CGPoint(x: -0.001, y: 60)) == nil)
        #expect(layout.verse(containing: CGPoint(x: layout.writingWidth + 0.001, y: 60)) == nil)
        #expect(layout.region(containing: CGPoint(x: 1_000, y: 1_000)) == nil)
    }

    @Test("절이 없는 레이아웃은 어떤 점도 소유하지 않는다")
    func emptyLayoutOwnsNothing() {
        let layout = builder.build(
            chapter: chapter,
            writingWidth: 320,
            setting: makeSetting(),
            isLeftHanded: false,
            verses: []
        )

        #expect(layout.verse(containing: .zero) == nil)
        #expect(layout.verse(containing: CGPoint(x: 10, y: 10)) == nil)
    }

    // MARK: - 레이아웃이 달라져도 규칙은 같다

    @Test("폭·행간이 달라져도 경계 규칙은 그대로 성립한다")
    func boundaryRuleHoldsForOtherLayouts() {
        let layout = makeLayout(writingWidth: 240, lineSpace: 12, metrics: .zero)

        // metrics 가 zero 이면 writingRect 가 맞닿아 captureRect 경계 = writingRect 경계다.
        #expect(layout.regions[0].captureRect.maxY == layout.regions[0].writingRect.maxY)
        #expect(layout.verse(containing: CGPoint(x: 1, y: layout.regions[0].writingRect.maxY)) == 2)

        for sampleY in stride(from: CGFloat(0), to: layout.totalHeight, by: 0.25) {
            let point = CGPoint(x: 1, y: sampleY)
            #expect(layout.regions.filter { $0.capturesPoint(point) }.count == 1)
        }
    }
}
