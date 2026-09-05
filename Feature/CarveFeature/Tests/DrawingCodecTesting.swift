//
//  DrawingCodecTesting.swift
//  CarveFeatureTest
//
//  Phase 3 — DrawingCodec: 합성(§6-4 · §9 · §10-2)과 편집 → 저장 명령(§8-2 · §7)
//  설계 §14 의 1 · 2 · 5-6 · 9 · 13 과 §7-1 미결(앵커가 캔버스 밖)의 ① 채택을 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing
import UIKit

@testable import CarveFeature

@Suite("Phase 3 — DrawingCodec")
struct DrawingCodecTesting {
    private let codec = DrawingCodec()
    /// 4절 · 줄 30pt · 폭 320. verse v 의 writingRect.minY = (v−1)×30, storageOrigin.y = v×30.
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
    private let columnOrigin = CGPoint(x: 100, y: 0)

    // MARK: 헬퍼

    private func data(_ strokes: [PKStroke]) -> Data {
        PKDrawing(strokes: strokes).dataRepresentation()
    }

    private func legacySnapshot(verse: Int, strokes: [PKStroke], rowKey: String) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowKey), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1), lineData: data(strokes), drawingVersion: 1, metadata: nil
        )
    }

    private func versionedSnapshot(verse: Int, strokes: [PKStroke], rowKey: String, baseWidth: CGFloat = 320) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowKey), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1), lineData: data(strokes), drawingVersion: 3,
            metadata: DrawingLayoutMetadata(
                baseWritingWidth: baseWidth, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "old"
            )
        )
    }

    private func stroke(_ from: CGPoint, _ to: CGPoint, seed: UInt32, time: TimeInterval = 1_000) -> PKStroke {
        OwnershipTestSupport.stroke(from: from, to: to, seed: seed, creationTime: time)
    }

    private func anchors(_ data: Data) throws -> [CGPoint] {
        try PKDrawing(data: data).strokes.compactMap { stroke in
            stroke.path.first.map { $0.location.applying(stroke.transform) }
        }
    }

    private func context(active: [Int: BibleDrawingRowID]) -> DrawingEditContext {
        DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: active)
    }

    // MARK: 합성

    @Test("legacy 행은 무변환으로 현재 writingRect 원점에 놓이고 소유권은 행의 절이다 (§14 13)")
    func legacyRowIsPlacedAtWritingRectOrigin() throws {
        let local = stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 1)
        let composed = codec.compose(
            snapshots: [legacySnapshot(verse: 2, strokes: [local], rowKey: "legacy-2")],
            layout: layout, columnOrigin: columnOrigin
        )

        // writingRect(verse 2).origin = (0, 30) + columnOrigin (100, 0)
        #expect(try anchors(composed.data) == [CGPoint(x: 110, y: 35)])
        #expect(composed.ownership.owner(of: StrokeIdentityKey(stroke: local)) == 2)
        #expect(composed.legacyVerses == [2])
        #expect(composed.layoutMismatchVerses.isEmpty)
        #expect(composed.activeRowIDs == [2: BibleDrawingRowID(raw: "legacy-2")])
    }

    @Test("drawingVersion 3 행은 첫 밑줄 기준으로 reflow 되어 현재 밑줄에 놓인다")
    func versionedRowIsReflowedToCurrentUnderline() throws {
        // 저장 좌표: 첫 밑줄 5pt 위. 현재 verse 1 의 첫 밑줄은 layout y 30.
        let stored = stroke(CGPoint(x: 10, y: -5), CGPoint(x: 20, y: -5), seed: 2)
        let composed = codec.compose(
            snapshots: [versionedSnapshot(verse: 1, strokes: [stored], rowKey: "v3-1")],
            layout: layout, columnOrigin: columnOrigin
        )

        #expect(try anchors(composed.data) == [CGPoint(x: 110, y: 25)])
        #expect(composed.legacyVerses.isEmpty)
        #expect(composed.ownership.owner(of: StrokeIdentityKey(stroke: stored)) == 1)
    }

    @Test("절당 여러 행이 있으면 대표 행만 합성된다")
    func onlyRepresentativeRowIsComposed() throws {
        let older = VerseDrawingSnapshot(
            verse: 1, rowID: BibleDrawingRowID(raw: "old"), isPresent: false,
            updateDate: Date(timeIntervalSince1970: 1), lineData: data([stroke(.zero, CGPoint(x: 5, y: 0), seed: 3)]),
            drawingVersion: 1, metadata: nil
        )
        let present = legacySnapshot(verse: 1, strokes: [stroke(CGPoint(x: 1, y: 1), CGPoint(x: 6, y: 1), seed: 4)], rowKey: "present")

        let composed = codec.compose(snapshots: [older, present], layout: layout, columnOrigin: columnOrigin)

        #expect(try PKDrawing(data: composed.data).strokes.count == 1)
        #expect(composed.activeRowIDs[1]?.raw == "present")
    }

    // MARK: 편집 → 저장 명령

    @Test("변경 없이 다시 계산하면 mutation 이 없다 (§14 9 라운드트립)")
    func unchangedDrawingProducesNoMutations() throws {
        let composed = codec.compose(
            snapshots: [
                versionedSnapshot(verse: 1, strokes: [stroke(CGPoint(x: 10, y: -5), CGPoint(x: 20, y: -5), seed: 5)], rowKey: "a"),
                legacySnapshot(verse: 2, strokes: [stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 6)], rowKey: "b")
            ],
            layout: layout, columnOrigin: columnOrigin
        )

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: composed.data, context: context(active: composed.activeRowIDs)
        )

        #expect(result.mutations.isEmpty)
        #expect(result.issuedRowIDs.isEmpty)
        #expect(result.ownership.map == composed.ownership.map)
    }

    @Test("행이 없는 절에 그은 획은 create 로, 여러 절을 지나도 시작 절에 통째로 저장된다 (§14 1 · §8-7)")
    func newStrokeCreatesRowInStartingVerseWithoutClipping() throws {
        let empty = codec.compose(snapshots: [], layout: layout, columnOrigin: columnOrigin)
        // content (110, 35) → layout (10, 35) = verse 2. 아래로 (10, 95) = verse 4 까지 관통.
        let crossing = stroke(CGPoint(x: 110, y: 35), CGPoint(x: 110, y: 95), seed: 7)

        let result = codec.mutations(
            beforeData: empty.data, beforeOwnership: empty.ownership,
            afterData: data([crossing]), context: context(active: [:])
        )

        #expect(result.mutations.count == 1)
        guard case .create(let verse, let rowID, let saved, let metadata) = try #require(result.mutations.first) else {
            Issue.record("create 가 아니다"); return
        }
        #expect(verse == 2)
        #expect(result.issuedRowIDs[2] == rowID)
        // 첫 밑줄(layout y 60) 원점의 verse-local. 잘리지 않고 마지막 점까지 그대로다.
        let decoded = try PKDrawing(data: saved)
        #expect(decoded.strokes.count == 1)
        #expect(try anchors(saved) == [CGPoint(x: 10, y: -25)])
        let last = try #require(decoded.strokes.first?.path.last?.location.applying(decoded.strokes.first!.transform))
        #expect(last == CGPoint(x: 10, y: 35))
        #expect(metadata.baseUnderlineAnchors == [0])
        #expect(metadata.layoutSignature == layout.signature)
        #expect(result.ownership.owner(of: StrokeIdentityKey(stroke: crossing)) == 2)
    }

    @Test("활성 행이 있는 절에 획을 더하면 replace 로, 첫 밑줄 원점으로 localize 된다")
    func addingStrokeToExistingVerseReplaces() throws {
        let existing = stroke(CGPoint(x: 10, y: -5), CGPoint(x: 20, y: -5), seed: 8)
        let composed = codec.compose(
            snapshots: [versionedSnapshot(verse: 1, strokes: [existing], rowKey: "row-1")],
            layout: layout, columnOrigin: columnOrigin
        )
        // content (140, 25) = layout (40, 25) → verse 1, 첫 밑줄(30) 5pt 위.
        let added = stroke(CGPoint(x: 140, y: 25), CGPoint(x: 150, y: 25), seed: 9)
        var strokes = try PKDrawing(data: composed.data).strokes
        strokes.append(added)

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: data(strokes), context: context(active: composed.activeRowIDs)
        )

        guard case .replace(let verse, let rowID, let saved, _) = try #require(result.mutations.first) else {
            Issue.record("replace 가 아니다"); return
        }
        #expect(result.mutations.count == 1)
        #expect(verse == 1)
        #expect(rowID.raw == "row-1")
        #expect(try anchors(saved) == [CGPoint(x: 10, y: -5), CGPoint(x: 40, y: -5)])
        #expect(result.issuedRowIDs.isEmpty)
    }

    @Test("절의 획을 전부 지우면 clear 가 나온다 — 행은 남긴다 (§14 2)")
    func erasingEveryStrokeYieldsClear() throws {
        let composed = codec.compose(
            snapshots: [
                legacySnapshot(verse: 2, strokes: [stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 10)], rowKey: "row-2"),
                legacySnapshot(verse: 3, strokes: [stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 11)], rowKey: "row-3")
            ],
            layout: layout, columnOrigin: columnOrigin
        )
        let remaining = try PKDrawing(data: composed.data).strokes.filter { composed.ownership.owner(of: $0) == 3 }

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: data(remaining), context: context(active: composed.activeRowIDs)
        )

        #expect(result.mutations == [.clear(verse: 2, rowID: BibleDrawingRowID(raw: "row-2"))])
        #expect(result.ownership.ownedVerses == [3])
    }

    @Test("mask 만 바뀐 획은 owner 를 유지하면서 dirty 로 판정된다 (§14 5-6)")
    func maskOnlyChangeIsDirtyButKeepsOwner() throws {
        let original = stroke(CGPoint(x: 10, y: -5), CGPoint(x: 60, y: -5), seed: 12)
        let composed = codec.compose(
            snapshots: [versionedSnapshot(verse: 1, strokes: [original], rowKey: "row-1")],
            layout: layout, columnOrigin: columnOrigin
        )
        let placed = try #require(try PKDrawing(data: composed.data).strokes.first)
        let masked = PKStroke(
            ink: placed.ink, path: placed.path, transform: placed.transform,
            mask: UIBezierPath(rect: CGRect(x: 0, y: -10, width: 20, height: 20)),
            randomSeed: placed.randomSeed
        )

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: data([masked]), context: context(active: composed.activeRowIDs)
        )

        #expect(result.mutations.count == 1)
        if case .replace(let verse, let rowID, _, _) = result.mutations[0] {
            #expect(verse == 1)
            #expect(rowID.raw == "row-1")
        } else {
            Issue.record("replace 가 아니다")
        }
        #expect(result.ownership.owner(of: StrokeIdentityKey(stroke: masked)) == 1)
    }

    @Test("바뀌지 않은 절은 mutation 을 만들지 않는다")
    func untouchedVersesAreLeftAlone() throws {
        let composed = codec.compose(
            snapshots: [
                legacySnapshot(verse: 1, strokes: [stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 13)], rowKey: "row-1"),
                legacySnapshot(verse: 3, strokes: [stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 14)], rowKey: "row-3")
            ],
            layout: layout, columnOrigin: columnOrigin
        )
        var strokes = try PKDrawing(data: composed.data).strokes
        strokes.append(stroke(CGPoint(x: 110, y: 75), CGPoint(x: 120, y: 75), seed: 15))   // layout y 75 → verse 3

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: data(strokes), context: context(active: composed.activeRowIDs)
        )

        #expect(result.mutations.map(\.verse) == [3])
    }

    @Test("앵커가 캔버스 밖이면 캔버스 안으로 클램프해 가장 가까운 절에 귀속된다 (§7-1 미결 ① 채택)")
    func anchorOutsideCanvasIsClamped() throws {
        let empty = codec.compose(snapshots: [], layout: layout, columnOrigin: columnOrigin)
        // content y −10 → layout y −10 (캔버스 위 bounce 구간) → 0 으로 클램프 → verse 1.
        let above = stroke(CGPoint(x: 110, y: -10), CGPoint(x: 120, y: 10), seed: 16)
        // content x 50 → layout x −50 (컬럼 왼쪽 밖) · y 100 → verse 4.
        let left = stroke(CGPoint(x: 50, y: 100), CGPoint(x: 120, y: 100), seed: 17)

        let result = codec.mutations(
            beforeData: empty.data, beforeOwnership: empty.ownership,
            afterData: data([above, left]), context: context(active: [:])
        )

        #expect(result.ownership.owner(of: StrokeIdentityKey(stroke: above)) == 1)
        #expect(result.ownership.owner(of: StrokeIdentityKey(stroke: left)) == 4)
        #expect(result.mutations.map(\.verse) == [1, 4])
    }

    @Test("실사용 blob 도 소수 columnOrigin 을 거친 직렬화 라운드트립에서 signature 가 바뀌지 않는다")
    func realBlobSurvivesSerializationRoundTripWithFractionalColumnOrigin() throws {
        let fractional = CGPoint(x: 366.7, y: 0)
        let snapshot = VerseDrawingSnapshot(
            verse: 1, rowID: BibleDrawingRowID(raw: "real"), isPresent: true, updateDate: nil,
            lineData: LegacyDrawingFixture.aboveOrigin.data, drawingVersion: 1, metadata: nil
        )
        let composed = codec.compose(snapshots: [snapshot], layout: layout, columnOrigin: fractional)
        // 캔버스가 다시 직렬화한 것을 흉내 낸다.
        let reserialized = try PKDrawing(data: composed.data).dataRepresentation()

        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership, afterData: reserialized,
            context: DrawingEditContext(layout: layout, columnOrigin: fractional, activeRowIDs: composed.activeRowIDs)
        )

        #expect(result.mutations.isEmpty)
    }
}
