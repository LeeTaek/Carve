//
//  VerseImageCardTesting.swift
//  CarveFeatureTest
//
//  절 이미지(시안 G1)를 실제로 그린다 — 출처 문구, 카드 폭, 필기가 없을 때 「나의 필사」 칸을 빼는지, 경계를 넘는 필기를 자르지 않는지.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing
import UIKit

@testable import CarveFeature

@Suite("G1 — 절 이미지 그리기")
@MainActor
struct VerseImageCardTesting {
    private static func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        OwnershipTestSupport.stroke(from: start, to: end, seed: 1, creationTime: 1_000)
    }

    private static func content(ink: [PKStroke]?) -> VerseImageContent {
        VerseImageContent(
            sentence: "여호와는 나의 목자시니 내가 부족함이 없으리로다",
            setting: .initialState,
            reference: VerseImageContent.reference(chapter: BibleChapter(title: .psalms, chapter: 23), verse: 1),
            handwriting: VerseImageHandwriting(
                verse: 1,
                writingSize: CGSize(width: 320, height: 60),
                underlineAnchors: [30, 60],
                inkData: ink.map { PKDrawing(strokes: $0).dataRepresentation() }
            )
        )
    }

    private static func renderedImage(_ content: VerseImageContent, scale: CGFloat) throws -> UIImage {
        let data = try #require(VerseImageCard.renderPNG(content, scale: scale))
        return try #require(UIImage(data: data))
    }

    @Test("출처는 「권 장 절 · 번역본」 이다 — 시편도 앱의 다른 화면처럼 「장」 으로 적는다")
    func referenceText() {
        #expect(VerseImageContent.reference(chapter: BibleChapter(title: .psalms, chapter: 23), verse: 1) == "시편 23장 1절 · 개역한글")
    }

    @Test("카드 폭은 필사 폭에 좌우 여백을 더한 것이고, 배율만큼 픽셀이 커진다")
    func rendersPNGWithCardWidth() throws {
        let content = Self.content(ink: [Self.stroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 200, y: 20))])

        let image = try Self.renderedImage(content, scale: 2)

        // PNG 를 다시 읽으면 배율 1 이라 크기가 곧 픽셀이다.
        #expect(image.size.width == VerseImageCard.cardWidth(for: content) * 2)
        #expect(VerseImageCard.cardWidth(for: content) == CGFloat(320 + 80))
    }

    @Test("필기가 없는 절은 「나의 필사」 칸을 빼 필기가 있을 때보다 짧다")
    func textOnlyImageIsShorter() throws {
        let withInk = try Self.renderedImage(Self.content(ink: [Self.stroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 200, y: 20))]), scale: 1)
        let textOnly = try Self.renderedImage(Self.content(ink: nil), scale: 1)

        #expect(textOnly.size.width == withInk.size.width)
        #expect(textOnly.size.height < withInk.size.height)
    }

    @Test("절 경계를 넘는 필기는 자르지 않는다 — 필기 칸이 필기 범위까지 늘어난다")
    func handwritingAreaIncludesOverflowingInk() throws {
        let handwriting = Self.content(ink: [Self.stroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 10, y: 200))]).handwriting

        let image = try #require(VerseImageCard.handwritingImage(handwriting, scale: 1))

        #expect(image.areaRect.minY == 0)
        #expect(image.areaRect.maxY >= 200)
        #expect(image.areaRect.width == 320)
    }
}
