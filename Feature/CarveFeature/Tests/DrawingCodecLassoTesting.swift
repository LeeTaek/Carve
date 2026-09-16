//
//  DrawingCodecLassoTesting.swift
//  CarveFeatureTest
//
//  올가미 — 절을 넘는 이동이 만드는 저장 명령 (§8-2 · 올가미 설계 §4-4 · §4-5)
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

/// 올가미로 절을 넘겨 옮기면 **떠난 절과 도착한 절이 함께** 저장된다.
///
/// 재귀속(§4-4)이 owner 를 바꾸면 그 다음은 기존 경로 그대로다 — dirty 집합이 두 절을 담고,
/// 절별 완전한 획 집합이 각자의 첫 밑줄 원점으로 localize 되어 한 batch 로 나간다 (§8-2 · §8-6).
@Suite("올가미 — 절을 넘는 이동의 저장 명령")
struct DrawingCodecLassoTesting {
    private let codec = DrawingCodec()
    /// 4절 · 줄 30pt · 폭 320. captureRect(layout): v1 [0,30) · v2 [30,60) · v3 [60,90) · v4 [90,120]
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
    private let columnOrigin = CGPoint(x: 100, y: 0)

    private func data(_ strokes: [PKStroke]) -> Data {
        PKDrawing(strokes: strokes).dataRepresentation()
    }

    private func stroke(_ from: CGPoint, _ to: CGPoint, seed: UInt32, time: TimeInterval = 1_000) -> PKStroke {
        OwnershipTestSupport.stroke(from: from, to: to, seed: seed, creationTime: time)
    }

    /// 올가미 이동 — `path` 는 그대로고 `transform` 만 바뀐다 (실측 L-2).
    private func moved(_ stroke: PKStroke, byY offsetY: CGFloat) -> PKStroke {
        PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: stroke.transform.concatenating(CGAffineTransform(translationX: 0, y: offsetY)),
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    private func ownership(_ pairs: [(PKStroke, Int)]) -> OwnershipSnapshot {
        var map: [StrokeIdentityKey: Int] = [:]
        for (stroke, verse) in pairs { map[StrokeIdentityKey(stroke: stroke)] = verse }
        return OwnershipSnapshot(map: map, layoutSignature: layout.signature)
    }

    private func context(active: [Int: BibleDrawingRowID]) -> DrawingEditContext {
        DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: active)
    }

    @Test("도착 절에 행이 없으면 떠난 절 clear · 도착 절 create 두 명령이 나온다")
    func moveToEmptyVerseClearsSourceAndCreatesDestination() throws {
        // content (110, 10) → layout (10, 10) = v1. 그 절의 유일한 획이다.
        let original = stroke(CGPoint(x: 110, y: 10), CGPoint(x: 200, y: 10), seed: 91)
        let row1 = BibleDrawingRowID(raw: "row-1")

        // 올가미로 +65 — layout y 75 = v3. 3절에는 행이 없다.
        let after = moved(original, byY: 65)

        let result = codec.mutations(
            beforeData: data([original]),
            beforeOwnership: ownership([(original, 1)]),
            afterData: data([after]),
            context: context(active: [1: row1])
        )

        #expect(result.ownership.owner(of: after) == 3)
        #expect(result.mutations.map(\.verse) == [1, 3])

        // 떠난 절 — 획이 남지 않았으니 비운다. 행은 지우지 않는다 (§8-7).
        #expect(result.mutations.first == .clear(verse: 1, rowID: row1))

        // 도착 절 — 행이 없으므로 rowID 를 선발급해 create 한다 (§8-7).
        guard case .create(let verse, let rowID, let saved, let metadata) = try #require(result.mutations.last) else {
            Issue.record("create 가 아니다"); return
        }
        #expect(verse == 3)
        #expect(result.issuedRowIDs == [3: rowID])
        #expect(try PKDrawing(data: saved).strokes.count == 1)
        #expect(metadata.layoutSignature == layout.signature)
    }

    @Test("도착 절에 이미 필기가 있으면 replace 로 합쳐진다")
    func moveIntoWrittenVerseReplacesWithBothStrokes() throws {
        let original = stroke(CGPoint(x: 110, y: 10), CGPoint(x: 200, y: 10), seed: 92)
        // content (110, 65) → layout (10, 65) = v3 에 이미 있는 획.
        let existing = stroke(CGPoint(x: 110, y: 65), CGPoint(x: 200, y: 65), seed: 93, time: 2_000)
        let row1 = BibleDrawingRowID(raw: "row-1")
        let row3 = BibleDrawingRowID(raw: "row-3")

        let after = moved(original, byY: 65)

        let result = codec.mutations(
            beforeData: data([original, existing]),
            beforeOwnership: ownership([(original, 1), (existing, 3)]),
            afterData: data([after, existing]),
            context: context(active: [1: row1, 3: row3])
        )

        #expect(result.mutations.map(\.verse) == [1, 3])
        #expect(result.mutations.first == .clear(verse: 1, rowID: row1))
        #expect(result.issuedRowIDs.isEmpty)

        guard case .replace(let verse, let rowID, let saved, _) = try #require(result.mutations.last) else {
            Issue.record("replace 가 아니다"); return
        }
        #expect(verse == 3)
        #expect(rowID == row3)
        // 그 절의 **완전한** 획 집합이다 (§8-3) — 원래 있던 획과 옮겨 온 획 둘.
        #expect(try PKDrawing(data: saved).strokes.count == 2)
    }

    @Test("같은 절 안의 이동은 그 절 하나만 replace 한다")
    func moveInsideSameVerseTouchesOneVerse() throws {
        let original = stroke(CGPoint(x: 110, y: 5), CGPoint(x: 200, y: 5), seed: 94)
        let row1 = BibleDrawingRowID(raw: "row-1")

        // layout y 5 → 20. 여전히 v1 이다.
        let after = moved(original, byY: 15)

        let result = codec.mutations(
            beforeData: data([original]),
            beforeOwnership: ownership([(original, 1)]),
            afterData: data([after]),
            context: context(active: [1: row1])
        )

        #expect(result.ownership.owner(of: after) == 1)
        #expect(result.mutations.map(\.verse) == [1])
        guard case .replace(_, let rowID, let saved, _) = try #require(result.mutations.first) else {
            Issue.record("replace 가 아니다"); return
        }
        #expect(rowID == row1)
        #expect(try PKDrawing(data: saved).strokes.count == 1)
    }
}
