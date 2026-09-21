//
//  StrokeOwnershipLassoTesting.swift
//  CarveFeatureTest
//
//  올가미 — §7-3 규칙 1'' (앵커 이동 재귀속). 설계: docs/lasso-design.md §4-4
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

/// 올가미로 옮긴 획은 **놓인 자리의 절**에 속한다.
///
/// 이동은 `path` 를 건드리지 않고 `transform` 만 바꾸므로 `StrokeIdentityKey` 가 그대로다 (2026-09-16 실측 L-2).
/// 규칙 1 에 앵커 불변 조건이 없으면 3절 자리에 보이는 잉크가 1절 행에 저장되고, 글자 크기 · 회전 때 1절을 따라간다
/// (같은 날 시뮬레이터에서 재현 — 올가미 설계 §5-2). 이 스위트가 그 조임을 고정한다.
@Suite("올가미 — §7-3 규칙 1'' 앵커 이동 재귀속")
struct StrokeOwnershipLassoTesting {
    private let resolver = StrokeOwnershipResolver()
    /// captureRect: v1 [0,30) · v2 [30,60) · v3 [60,90) · v4 [90,120]
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)

    /// 올가미 이동 — `path` · `mask` · `randomSeed` 는 그대로 두고 `transform` 만 더한다 (실측 L-2).
    private func moved(_ stroke: PKStroke, byY offsetY: CGFloat) -> PKStroke {
        PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: stroke.transform.concatenating(CGAffineTransform(translationX: 0, y: offsetY)),
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    private func baseline(_ strokes: [PKStroke]) -> (drawing: PKDrawing, ownership: OwnershipSnapshot) {
        let drawing = PKDrawing(strokes: strokes)
        return (drawing, resolver.resolve(drawing: drawing, layout: layout))
    }

    @Test("옮긴 획은 IdentityKey 가 같아도 놓인 절로 재귀속된다")
    func movedStrokeIsReanchoredToDroppedVerse() {
        let original = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10), seed: 77, creationTime: 5_000
        )
        let before = baseline([original])
        #expect(before.ownership.owner(of: original) == 1)

        // 앵커 y 10 → 75. v3 [60,90) 이다.
        let after = moved(original, byY: 65)
        let ownership = resolver.reconcile(
            previous: before.ownership, previousDrawing: before.drawing,
            drawing: PKDrawing(strokes: [after]), layout: layout
        )

        // 키가 같은데도 owner 가 바뀌는 것이 이 규칙의 전부다.
        #expect(StrokeIdentityKey(stroke: after) == StrokeIdentityKey(stroke: original))
        #expect(ownership.owner(of: after) == 3)
        #expect(ownership.ownedVerses == [3])
    }

    @Test("되돌리면 원래 절로 돌아온다 — 이동의 undo 도 같은 규칙이 처리한다")
    func undoOfMoveReturnsOwnershipToOriginalVerse() {
        let original = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10), seed: 77, creationTime: 5_000
        )
        let before = baseline([original])
        let movedStroke = moved(original, byY: 65)
        let afterMove = resolver.reconcile(
            previous: before.ownership, previousDrawing: before.drawing,
            drawing: PKDrawing(strokes: [movedStroke]), layout: layout
        )
        #expect(afterMove.owner(of: movedStroke) == 3)

        // 실행 취소 — PencilKit 이 transform 을 원래 값으로 되돌린다 (실측 L-4).
        let restored = resolver.reconcile(
            previous: afterMove, previousDrawing: PKDrawing(strokes: [movedStroke]),
            drawing: PKDrawing(strokes: [original]), layout: layout
        )

        #expect(restored.owner(of: original) == 1)
        #expect(restored.ownedVerses == [1])
    }

    @Test("같은 절 안에서 옮기면 그 절 그대로다")
    func moveInsideSameVerseKeepsOwner() {
        let original = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 5), to: CGPoint(x: 100, y: 5), seed: 78, creationTime: 5_000
        )
        let before = baseline([original])
        // 앵커 y 5 → 20. 여전히 v1 [0,30) 이다.
        let after = moved(original, byY: 15)

        let ownership = resolver.reconcile(
            previous: before.ownership, previousDrawing: before.drawing,
            drawing: PKDrawing(strokes: [after]), layout: layout
        )

        #expect(ownership.owner(of: after) == 1)
    }

    @Test("옮긴 획은 겹침(규칙 3)이 아니라 앵커로 간다 — 다른 절 잉크 위에 놓아도 놓인 절이다")
    func movedStrokeUsesAnchorNotOverlap() {
        // 위로 올라가는 획이라 앵커(첫 control point)는 아래쪽 끝이다.
        let rising = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 25), to: CGPoint(x: 10, y: 10), seed: 81, creationTime: 5_000
        )
        // v2 에 넓게 깔린 이전 세대 잉크. 옮긴 획의 몸통이 이 위를 지난다.
        let neighbour = OwnershipTestSupport.stroke(
            from: CGPoint(x: 5, y: 45), to: CGPoint(x: 200, y: 50), seed: 82, creationTime: 6_000
        )
        let before = baseline([rising, neighbour])
        #expect(before.ownership.owner(of: rising) == 1)
        #expect(before.ownership.owner(of: neighbour) == 2)

        // 앵커 y 25 → 65 (v3). 몸통은 y 50…65 라 v2 의 이웃 잉크와 겹친다.
        let after = moved(rising, byY: 40)
        #expect(after.renderBounds.intersects(neighbour.renderBounds))

        let ownership = resolver.reconcile(
            previous: before.ownership, previousDrawing: before.drawing,
            drawing: PKDrawing(strokes: [after, neighbour]), layout: layout
        )

        // 규칙 3 이 먼저 걸리면 겹치는 v2 가 되고, 재귀속이 걸리면 앵커의 v3 가 된다.
        #expect(ownership.owner(of: after) == 3)
        #expect(ownership.owner(of: neighbour) == 2)
    }

    @Test("캔버스 밖으로 옮기면 owner 가 없다 — 클램프는 코덱(U8)의 몫이다")
    func moveOutsideCanvasLosesOwner() {
        let original = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10), seed: 79, creationTime: 5_000
        )
        let before = baseline([original])
        // 앵커 y 10 → 310. 마지막 captureRect 의 maxY(120)보다 아래다.
        let after = moved(original, byY: 300)

        let ownership = resolver.reconcile(
            previous: before.ownership, previousDrawing: before.drawing,
            drawing: PKDrawing(strokes: [after]), layout: layout
        )

        #expect(ownership.owner(of: after) == nil)
        #expect(ownership.map.isEmpty)
    }

    @Test("지우개 조각은 앵커가 원본과 같아 승계가 유지된다 (S1-2 — 재귀속이 지우개 경로를 건드리지 않는다)")
    func bitmapEraseKeepsAnchorSoInheritanceSurvives() throws {
        let beforeDrawing = try OwnershipTestSupport.decoded(EraserFixture.beforeErase)
        let beforeOwnership = resolver.resolve(drawing: beforeDrawing, layout: layout)
        let afterDrawing = try OwnershipTestSupport.decoded(EraserFixture.afterPartialErase)

        // 규칙 1' 의 전제 — 조각들의 앵커가 원본과 같다. 이것이 깨지면 지우개가 재귀속 경로로 새어 나간다.
        #expect(anchors(of: beforeDrawing, seed: 956_091_164) == anchors(of: afterDrawing, seed: 956_091_164))

        let ownership = resolver.reconcile(
            previous: beforeOwnership, previousDrawing: beforeDrawing,
            drawing: afterDrawing, layout: layout
        )

        let fragments = afterDrawing.strokes.filter { $0.randomSeed == 956_091_164 }
        #expect(fragments.count == 2)
        #expect(fragments.allSatisfy { ownership.owner(of: $0) == 1 })
        #expect(ownership.ownedVerses == [1, 2])
    }

    private func anchors(of drawing: PKDrawing, seed: UInt32) -> Set<CGPoint> {
        Set(drawing.strokes.filter { $0.randomSeed == seed }.compactMap { resolver.anchorPoint(of: $0) })
    }
}
