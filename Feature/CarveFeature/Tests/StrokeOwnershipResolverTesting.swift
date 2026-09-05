//
//  StrokeOwnershipResolverTesting.swift
//  CarveFeatureTest
//
//  Phase 0B — 획 소유권 판정(§7-1)과 승계(§7-3)
//  단일 Canvas 설계(docs/single-canvas-design.md) 의 순수 로직을 UI 없이 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

// MARK: - 공용 헬퍼

/// 두 테스트 스위트가 공유하는 레이아웃·stroke 생성기.
enum OwnershipTestSupport {
    static let chapter = BibleChapter(title: .genesis, chapter: 1)

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

    /// 절마다 한 줄짜리 균일 레이아웃. captureRect 는 `[0, lineSpace)`, `[lineSpace, 2 × lineSpace)` … 로 나뉜다.
    static func uniformLayout(verseCount: Int, lineSpace: CGFloat, writingWidth: CGFloat = 320) -> ChapterLayout {
        ChapterLayoutBuilder().build(
            chapter: chapter,
            writingWidth: writingWidth,
            setting: setting(lineSpace: lineSpace),
            isLeftHanded: false,
            verses: (1...verseCount).map { VerseLayoutInput(verse: $0, textLineCount: 1) }
        )
    }

    /// 직선 stroke 하나. 좌표는 **로컬**이며 `transform` 이 로컬 → 캔버스 변환이다.
    static func stroke(
        from start: CGPoint,
        to end: CGPoint,
        seed: UInt32,
        creationTime: TimeInterval,
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        let steps = 8
        let points = (0...steps).map { index -> PKStrokePoint in
            let ratio = CGFloat(index) / CGFloat(steps)
            return PKStrokePoint(
                location: CGPoint(
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio
                ),
                timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: creationTime))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, transform: transform, mask: nil, randomSeed: seed)
    }

    static func decoded(_ base64: String) throws -> PKDrawing {
        let data = try #require(Data(base64Encoded: base64))
        return try PKDrawing(data: data)
    }
}

// MARK: - §7-1 소유권 판정

@Suite("Phase 0B — §7-1 획 소유권 판정")
struct StrokeOwnershipResolverTesting {
    private let resolver = StrokeOwnershipResolver()
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)

    @Test("첫 control point 가 속한 절이 owner 가 된다")
    func ownerIsVerseOfFirstControlPoint() {
        let stroke = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 41.5),
            to: CGPoint(x: 60, y: 45),
            seed: 1,
            creationTime: 1_000
        )

        #expect(resolver.anchorPoint(of: stroke) == CGPoint(x: 10, y: 41.5))
        #expect(resolver.owner(of: stroke, in: layout) == 2)
    }

    @Test("여러 절을 지나는 획도 시작한 절에 통째로 귀속된다 (U1 / P1 — 자르지 않는다)")
    func strokeCrossingVersesBelongsEntirelyToStartingVerse() {
        // y 5 → 115. 4개 절을 모두 관통한다.
        let stroke = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 5),
            to: CGPoint(x: 10, y: 115),
            seed: 7,
            creationTime: 1_000
        )
        let drawing = PKDrawing(strokes: [stroke])

        let ownership = resolver.resolve(drawing: drawing, layout: layout)

        // 시작 절 하나에만 귀속되고, 통과한 절들에는 어떤 조각도 남지 않는다.
        #expect(resolver.owner(of: stroke, in: layout) == 1)
        #expect(ownership.ownedVerses == [1])
        #expect(ownership.map.count == 1)
        #expect(drawing.strokes.count == 1)
    }

    @Test("앵커는 stroke 자신의 첫 control point 다 — drawing 의 첫 획이 아니다")
    func anchorIsPerStrokeNotPerDrawing() {
        let first = OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: 5), to: CGPoint(x: 60, y: 8), seed: 1, creationTime: 1_000)
        let second = OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: 95), to: CGPoint(x: 60, y: 98), seed: 2, creationTime: 2_000)

        let ownership = resolver.resolve(drawing: PKDrawing(strokes: [first, second]), layout: layout)

        // 한 번의 pen-down 이 복수 획을 만들거나 startPoint 가 nil 인 undo/redo 를 모두 덮기 위한 규칙(§5).
        #expect(ownership.owner(of: first) == 1)
        #expect(ownership.owner(of: second) == 4)
    }

    @Test("transform 을 적용한 뒤 판정한다 — 로컬 좌표로 판정하면 owner 가 어긋난다")
    func anchorAppliesStrokeTransform() {
        let stroke = OwnershipTestSupport.stroke(
            from: .zero,
            to: CGPoint(x: 50, y: 0),
            seed: 3,
            creationTime: 1_000,
            transform: CGAffineTransform(translationX: 5, y: 95)
        )

        #expect(stroke.path.first?.location == .zero)                       // 로컬 좌표는 원점
        #expect(resolver.anchorPoint(of: stroke) == CGPoint(x: 5, y: 95))   // 캔버스 좌표는 v4
        #expect(resolver.owner(of: stroke, in: layout) == 4)
    }

    @Test("캔버스 밖에서 시작한 획은 owner 가 없고 map 에도 들어가지 않는다")
    func strokeStartingOutsideCanvasHasNoOwner() {
        let below = OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: 500), to: CGPoint(x: 60, y: 505), seed: 4, creationTime: 1_000)
        let rightOfCanvas = OwnershipTestSupport.stroke(from: CGPoint(x: 400, y: 10), to: CGPoint(x: 420, y: 15), seed: 5, creationTime: 2_000)

        #expect(resolver.owner(of: below, in: layout) == nil)
        #expect(resolver.owner(of: rightOfCanvas, in: layout) == nil)
        #expect(resolver.resolve(drawing: PKDrawing(strokes: [below, rightOfCanvas]), layout: layout).map.isEmpty)
    }

    @Test("빈 drawing 은 빈 소유권을 만들고 layoutSignature 만 기록한다")
    func emptyDrawingProducesEmptyOwnership() {
        let ownership = resolver.resolve(drawing: PKDrawing(), layout: layout)

        #expect(ownership.map.isEmpty)
        #expect(ownership.layoutSignature == layout.signature)
    }
}

// MARK: - §7-3 승계

@Suite("Phase 0B — §7-3 소유권 승계")
struct StrokeOwnershipReconcileTesting {
    private let resolver = StrokeOwnershipResolver()
    /// captureRect: v1 [0,30) · v2 [30,60) · v3 [60,90) · v4 [90,120]
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)

    /// EraserFixture 의 두 원본 획. 첫 control point 는 각각 (53, 11.5) / (53, 41.5) 이므로
    /// 위 레이아웃에서 v1 / v2 로 갈린다.
    private func eraserBaseline() throws -> (drawing: PKDrawing, ownership: OwnershipSnapshot) {
        let before = try OwnershipTestSupport.decoded(EraserFixture.beforeErase)
        return (before, resolver.resolve(drawing: before, layout: layout))
    }

    // MARK: 규칙 1 — IdentityKey 완전 일치

    @Test("EraserFixture: 지우기 전 두 획이 서로 다른 절에 귀속된다")
    func fixtureBaselineSplitsAcrossVerses() throws {
        let (before, ownership) = try eraserBaseline()

        #expect(before.strokes.count == 2)
        #expect(ownership.owner(of: before.strokes[0]) == 1)   // seed 956091164, 앵커 (53, 11.5)
        #expect(ownership.owner(of: before.strokes[1]) == 2)   // seed 491497907, 앵커 (53, 41.5)
        #expect(ownership.ownedVerses == [1, 2])
    }

    @Test("EraserFixture: bitmap 지우개가 나눈 조각들이 모두 원본 owner 를 승계한다 (S1-2)")
    func bitmapEraseFragmentsInheritOriginalOwner() throws {
        let (before, baseline) = try eraserBaseline()
        let after = try OwnershipTestSupport.decoded(EraserFixture.afterPartialErase)

        let ownership = resolver.reconcile(
            previous: baseline,
            previousDrawing: before,
            drawing: after,
            layout: layout
        )

        // 획 하나의 중간만 지웠는데 엔트리는 2 → 3 으로 늘었다.
        #expect(after.strokes.count == 3)
        let fragments = after.strokes.filter { $0.randomSeed == 956_091_164 }
        #expect(fragments.count == 2)
        // 조각 전부가 원본과 같은 IdentityKey 를 가지므로 1번 규칙만으로 같은 owner 를 받는다.
        #expect(Set(fragments.map { StrokeIdentityKey(stroke: $0) }).count == 1)
        #expect(fragments.map { ownership.owner(of: $0) } == [1, 1])
        // 손대지 않은 획도 그대로다.
        #expect(ownership.owner(of: after.strokes[2]) == 2)
        #expect(ownership.ownedVerses == [1, 2])
    }

    @Test("§7-2 금지: map.count 는 stroke 개수가 아니다")
    func mapCountIsNotStrokeCount() throws {
        let (before, baseline) = try eraserBaseline()
        let after = try OwnershipTestSupport.decoded(EraserFixture.afterPartialErase)

        let ownership = resolver.reconcile(previous: baseline, previousDrawing: before, drawing: after, layout: layout)

        // stroke 3개 ↔ 키 2개. 이 차이가 map 을 stroke 열거에 쓰면 안 되는 이유다.
        #expect(after.strokes.count == 3)
        #expect(ownership.map.count == 2)
    }

    @Test("EraserFixture: 완전히 지운 획은 map 에서도 정리된다 (S1-3)")
    func fullyErasedStrokeIsRemovedFromOwnershipMap() throws {
        let (before, baseline) = try eraserBaseline()
        let erasedKey = StrokeIdentityKey(stroke: before.strokes[1])
        let afterFull = try OwnershipTestSupport.decoded(EraserFixture.afterFullErase)

        let ownership = resolver.reconcile(
            previous: baseline,
            previousDrawing: before,
            drawing: afterFull,
            layout: layout
        )

        // 완전히 지운 stroke 는 drawing.strokes 에서 사라지므로 map 에도 남지 않는다.
        #expect(afterFull.strokes.count == 2)
        #expect(baseline.owner(of: erasedKey) == 2)
        #expect(ownership.owner(of: erasedKey) == nil)
        #expect(ownership.map.count == 1)
        #expect(ownership.ownedVerses == [1])
    }

    @Test("EraserFixture: 부분 지우기 → 완전 지우기 를 순서대로 승계해도 결과가 같다")
    func sequentialEraseStepsPreserveOwnership() throws {
        let (before, baseline) = try eraserBaseline()
        let partial = try OwnershipTestSupport.decoded(EraserFixture.afterPartialErase)
        let full = try OwnershipTestSupport.decoded(EraserFixture.afterFullErase)

        let afterPartial = resolver.reconcile(previous: baseline, previousDrawing: before, drawing: partial, layout: layout)
        let afterFull = resolver.reconcile(previous: afterPartial, previousDrawing: partial, drawing: full, layout: layout)

        #expect(afterFull.map.count == 1)
        #expect(full.strokes.allSatisfy { afterFull.owner(of: $0) == 1 })
    }

    @Test("승계는 dirty 판정을 대신하지 않는다 — 조각들은 ContentSignature 가 서로 다르다 (§7-2)")
    func contentSignatureDistinguishesEraseWhileIdentityDoesNot() throws {
        let before = try OwnershipTestSupport.decoded(EraserFixture.beforeErase)
        let after = try OwnershipTestSupport.decoded(EraserFixture.afterPartialErase)
        let original = try #require(before.strokes.first { $0.randomSeed == 956_091_164 })
        let fragments = after.strokes.filter { $0.randomSeed == 956_091_164 }

        // identity 는 같다 → 승계는 성립한다.
        #expect(fragments.allSatisfy { StrokeIdentityKey(stroke: $0) == StrokeIdentityKey(stroke: original) })
        // 반면 content signature 는 mask 때문에 전부 다르다 → 지우기가 dirty 로 잡힌다 (D7 방지).
        let signatures = Set(fragments.map { StrokeContentSignature(stroke: $0) })
        #expect(signatures.count == 2)
        #expect(!signatures.contains(StrokeContentSignature(stroke: original)))
        // 손대지 않은 획의 signature 는 그대로 유지된다.
        let untouchedBefore = try #require(before.strokes.first { $0.randomSeed == 491_497_907 })
        let untouchedAfter = try #require(after.strokes.first { $0.randomSeed == 491_497_907 })
        #expect(StrokeContentSignature(stroke: untouchedBefore) == StrokeContentSignature(stroke: untouchedAfter))
    }

    // MARK: 리플로우 — 승계가 존재하는 이유

    @Test("레이아웃이 바뀌어도 owner 는 재판정되지 않고 승계된다 (P2 / §7-3)")
    func ownershipSurvivesReflow() throws {
        let (before, baseline) = try eraserBaseline()
        // 폭과 행간이 모두 달라진 레이아웃. captureRect: v1 [0,12) v2 [12,24) v3 [24,36) v4 [36,48]
        let reflowed = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 12, writingWidth: 240)
        #expect(reflowed.signature != layout.signature)

        // 전량 재판정하면 두 번째 획의 소유권이 v2 → v4 로 흘러간다. 이것이 승계가 필요한 이유다.
        let reResolved = resolver.resolve(drawing: before, layout: reflowed)
        #expect(reResolved.owner(of: before.strokes[1]) == 4)

        let inherited = resolver.reconcile(
            previous: baseline,
            previousDrawing: before,
            drawing: before,
            layout: reflowed
        )

        #expect(inherited.map == baseline.map)                       // 소유권은 그대로
        #expect(inherited.owner(of: before.strokes[1]) == 2)
        #expect(inherited.layoutSignature == reflowed.signature)     // 좌표계 표시만 갱신
    }

    @Test("승계할 것이 없는 reconcile 은 전량 재판정(resolve)과 같다")
    func reconcileWithoutPreviousEqualsFreshResolve() throws {
        let before = try OwnershipTestSupport.decoded(EraserFixture.beforeErase)

        let resolved = resolver.resolve(drawing: before, layout: layout)
        let reconciled = resolver.reconcile(
            previous: .empty(layoutSignature: layout.signature),
            previousDrawing: PKDrawing(),
            drawing: before,
            layout: layout
        )

        #expect(resolved == reconciled)
    }

    // MARK: 규칙 3 — 공간 겹침 fallback 과 결정성

    /// 이전 세대 획 2개와, 그 둘 사이를 세로로 가로지르는 새 획 하나.
    private func overlapScenario(tallSecond: Bool) -> (previous: [PKStroke], candidate: PKStroke) {
        let first = OwnershipTestSupport.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), seed: 11, creationTime: 1_000)
        let second = tallSecond
            ? OwnershipTestSupport.stroke(from: CGPoint(x: 100, y: 280), to: CGPoint(x: 200, y: 320), seed: 22, creationTime: 2_000)
            : OwnershipTestSupport.stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 200, y: 300), seed: 22, creationTime: 2_000)
        let candidate = OwnershipTestSupport.stroke(from: CGPoint(x: 140, y: 60), to: CGPoint(x: 140, y: 340), seed: 33, creationTime: 3_000)
        return ([first, second], candidate)
    }

    private func overlapArea(_ lhs: PKStroke, _ rhs: PKStroke) -> CGFloat {
        let intersection = lhs.renderBounds.intersection(rhs.renderBounds)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    @Test("IdentityKey 도 없고 겹침도 없으면 첫 control point 로 신규 귀속된다 (규칙 4)")
    func unmatchedStrokeFallsBackToCaptureRect() {
        let tall = OwnershipTestSupport.uniformLayout(verseCount: 5, lineSpace: 100)
        let (previous, candidate) = overlapScenario(tallSecond: false)
        let previousDrawing = PKDrawing(strokes: previous)
        // 이전 획들의 owner 를 모르는 상태 → 겹침 후보가 없다.
        let ownership = resolver.reconcile(
            previous: .empty(layoutSignature: tall.signature),
            previousDrawing: previousDrawing,
            drawing: PKDrawing(strokes: [candidate]),
            layout: tall
        )

        // 앵커 (140, 60) → v1
        #expect(ownership.owner(of: candidate) == 1)
    }

    @Test("겹침이 동점이면 절 번호가 작은 쪽을 고른다 — 삽입 순서를 섞어도 같다 (§7-3 결정적 순서)")
    func overlapTieBreaksByAscendingVerseDeterministically() {
        let tall = OwnershipTestSupport.uniformLayout(verseCount: 5, lineSpace: 100)
        let (previous, candidate) = overlapScenario(tallSecond: false)
        // 전제 확인 — 두 후보의 겹침 면적이 실제로 같아야 동점 테스트가 성립한다.
        #expect(overlapArea(candidate, previous[0]) == overlapArea(candidate, previous[1]))

        // 절 번호를 일부러 역순으로 준다. "먼저 만난 것" 이 아니라 "번호가 작은 것" 이 이겨야 한다.
        let owners = [(previous[0], 5), (previous[1], 2)]

        for _ in 0..<50 {
            var map: [StrokeIdentityKey: Int] = [:]
            for (stroke, verse) in owners.shuffled() {
                map[StrokeIdentityKey(stroke: stroke)] = verse
            }
            let ownership = resolver.reconcile(
                previous: OwnershipSnapshot(map: map, layoutSignature: tall.signature),
                previousDrawing: PKDrawing(strokes: previous.shuffled()),
                drawing: PKDrawing(strokes: (previous + [candidate]).shuffled()),
                layout: tall
            )

            // 규칙 4 였다면 v1 이 나왔을 자리에 규칙 3 의 결과가 온다.
            #expect(ownership.owner(of: candidate) == 2)
            #expect(ownership.owner(of: previous[0]) == 5)
            #expect(ownership.owner(of: previous[1]) == 2)
        }
    }

    @Test("겹침 면적이 다르면 절 번호와 무관하게 더 많이 겹치는 owner 를 승계한다")
    func overlapWinnerIsLargestAreaNotSmallestVerse() {
        let tall = OwnershipTestSupport.uniformLayout(verseCount: 5, lineSpace: 100)
        let (previous, candidate) = overlapScenario(tallSecond: true)
        #expect(overlapArea(candidate, previous[1]) > overlapArea(candidate, previous[0]))

        var map: [StrokeIdentityKey: Int] = [:]
        map[StrokeIdentityKey(stroke: previous[0])] = 1
        map[StrokeIdentityKey(stroke: previous[1])] = 4

        for _ in 0..<20 {
            let ownership = resolver.reconcile(
                previous: OwnershipSnapshot(map: map, layoutSignature: tall.signature),
                previousDrawing: PKDrawing(strokes: previous.shuffled()),
                drawing: PKDrawing(strokes: (previous + [candidate]).shuffled()),
                layout: tall
            )

            #expect(ownership.owner(of: candidate) == 4)
        }
    }
}
