//
//  DrawingCodecVerseImageInkTesting.swift
//  CarveFeatureTest
//
//  절 이미지(시안 G1)의 필기 — 캔버스에 보이는 그대로(현재 밑줄에 재배치)를 필사 영역 좌상단 원점으로 옮기는지.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

@Suite("G1 — DrawingCodec · 절 이미지 필기")
struct DrawingCodecVerseImageInkTesting {
    /// 저장 행의 좌표 형식.
    enum Format: CaseIterable, Sendable {
        /// `drawingVersion` 1 — 필사 영역 원점에 무변환 배치.
        case legacy
        /// v3 인데 metadata 가 없다 — 첫 밑줄 원점에 통째 배치.
        case versionedWithoutMetadata
        /// v3 + metadata — 현재 밑줄에 재배치.
        case versioned
    }

    private let codec = DrawingCodec()
    /// 4절 · 줄 30pt · 폭 320.
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)

    private func snapshot(verse: Int, strokes: [PKStroke], format: Format, region: VerseCanvasRegion) -> VerseDrawingSnapshot {
        let data = PKDrawing(strokes: strokes).dataRepresentation()
        return switch format {
        case .legacy:
            VerseDrawingSnapshot(verse: verse, rowID: BibleDrawingRowID(raw: "row"), isPresent: true, updateDate: nil,
                                 lineData: data, drawingVersion: 1, metadata: nil)
        case .versionedWithoutMetadata:
            VerseDrawingSnapshot(verse: verse, rowID: BibleDrawingRowID(raw: "row"), isPresent: true, updateDate: nil,
                                 lineData: data, drawingVersion: 3, metadata: nil)
        case .versioned:
            VerseDrawingSnapshot(verse: verse, rowID: BibleDrawingRowID(raw: "row"), isPresent: true, updateDate: nil,
                                 lineData: data, drawingVersion: 3,
                                 metadata: DrawingLayoutMetadata(region: region, layoutSignature: layout.signature))
        }
    }

    private func stroke(_ from: CGPoint, _ to: CGPoint) -> PKStroke {
        OwnershipTestSupport.stroke(from: from, to: to, seed: 1, creationTime: 1_000)
    }

    /// 획마다 첫 control point 의 위치(transform 적용).
    private func anchors(_ data: Data) throws -> [CGPoint] {
        try PKDrawing(data: data).strokes.compactMap { stroke in
            stroke.path.first.map { $0.location.applying(stroke.transform) }
        }
    }

    @Test("화면 합성과 같은 자리에 놓는다 — 합성 결과를 필사 영역 원점으로 옮긴 것과 같다", arguments: Format.allCases)
    func matchesComposedPlacement(format: Format) throws {
        let region = try #require(layout.region(verse: 2))
        let row = snapshot(verse: 2, strokes: [stroke(CGPoint(x: 20, y: -6), CGPoint(x: 80, y: -6))], format: format, region: region)

        let composed = codec.compose(snapshots: [row], layout: layout, columnOrigin: .zero)
        let shown = try #require(anchors(composed.data).first)
        let ink = try #require(codec.verseImageInk(of: row, in: region))
        let local = try #require(anchors(ink).first)

        #expect(abs(local.x - (shown.x - region.writingRect.minX)) < 0.5)
        #expect(abs(local.y - (shown.y - region.writingRect.minY)) < 0.5)
    }

    @Test("현재 레이아웃에서 쓴 필기는 첫 밑줄 기준 좌표가 필사 영역 기준으로 바뀐다")
    func versionedInkIsOffsetByFirstUnderline() throws {
        let region = try #require(layout.region(verse: 2))
        let firstUnderline = try #require(region.underlineAnchors.first)
        let row = snapshot(verse: 2, strokes: [stroke(CGPoint(x: 20, y: -6), CGPoint(x: 80, y: -6))], format: .versioned, region: region)

        let ink = try #require(codec.verseImageInk(of: row, in: region))
        let local = try #require(anchors(ink).first)

        #expect(abs(local.x - 20) < 0.5)
        #expect(abs(local.y - (firstUnderline - 6)) < 0.5)
    }

    @Test("절 경계를 넘는 획도 자르지 않고 통째로 담는다")
    func overflowingStrokeIsKept() throws {
        let region = try #require(layout.region(verse: 2))
        let row = snapshot(verse: 2, strokes: [stroke(CGPoint(x: 20, y: -6), CGPoint(x: 20, y: 120))], format: .legacy, region: region)

        let bounds = try PKDrawing(data: try #require(codec.verseImageInk(of: row, in: region))).bounds

        #expect(bounds.maxY > region.writingRect.height)
    }

    @Test("획이 없거나 디코드하지 못하면 필기가 없다")
    func emptyOrUndecodableInkIsNil() throws {
        let region = try #require(layout.region(verse: 1))
        let rows = [nil, PKDrawing().dataRepresentation(), Data([1, 2, 3])].map { data in
            VerseDrawingSnapshot(verse: 1, rowID: BibleDrawingRowID(raw: "row"), isPresent: true, updateDate: nil,
                                 lineData: data, drawingVersion: 3, metadata: nil)
        }

        for row in rows {
            #expect(codec.verseImageInk(of: row, in: region) == nil)
        }
    }
}
