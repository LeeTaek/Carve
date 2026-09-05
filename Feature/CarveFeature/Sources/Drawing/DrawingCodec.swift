//
//  DrawingCodec.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit

// MARK: - 결과 타입

/// 장 합성 결과 (설계 §6-4 · §7-3 "DB 의 절별 그룹이 진실").
struct ComposedChapterDrawing: Equatable, Sendable {
    /// 캔버스 **content** 좌표의 drawing (`columnOrigin` 적용 완료). Coordinator 가 그대로 `PKCanvasView.drawing` 에 넣는다.
    let data: Data
    /// 원본 획 → 절. DB 행 그룹에서 유도한 것이라 기하 판정을 거치지 않았다.
    let ownership: OwnershipSnapshot
    /// 절별 활성 행 (§8-7). 대표 행이 없는 절은 없다.
    let activeRowIDs: [Int: BibleDrawingRowID]
    /// §9-3-1 로 처리된 절. 표시 상태이며 DB 에 기록하지 않는다.
    let layoutMismatchVerses: Set<Int>
    /// metadata 없이 무변환 배치한 절 (§10-2 — `drawingVersion` nil/1). 복구 로그·사용자 확인 대상.
    let legacyVerses: Set<Int>
}

/// 편집 하나의 계산 결과 (설계 §8-2).
struct DrawingEditResult: Equatable, Sendable {
    /// 편집 후 소유권 (승계 반영).
    let ownership: OwnershipSnapshot
    /// 절 오름차순의 저장 명령. dirty 가 아닌 절은 없다.
    let mutations: [VerseDrawingMutation]
    /// 이번 편집에서 새로 발급한 rowID (`create`). Feature 는 이것을 `activeRowIDs` 에 **즉시 예약**한다 (§8-7).
    let issuedRowIDs: [Int: BibleDrawingRowID]
}

/// 편집 계산에 필요한 문맥.
struct DrawingEditContext: Sendable {
    let layout: ChapterLayout
    /// 캔버스 content 좌표 = layout 좌표 + `columnOrigin` (§5).
    let columnOrigin: CGPoint
    /// 절별 활성 행. 없으면 `create` 가 된다.
    let activeRowIDs: [Int: BibleDrawingRowID]
}

// MARK: - 코덱

/// PencilKit 을 아는 **유일한** 변환 지점 (설계 §4 — 합성 / 소유권 / reconcile / reflow / transform 적용).
///
/// 상태도 부수효과도 없다. Reducer(`ChapterCanvasFeature`)는 이 타입이 돌려주는 `Data` 와 DTO 만 다룬다 (P9).
///
/// ## 좌표계 세 가지 — 변환은 전부 여기서만 일어난다 (§4 "좌표 관련 책임 분리")
///
/// | 좌표계 | 원점 | 쓰는 곳 |
/// |---|---|---|
/// | 저장 (verse-local) | 절의 첫 밑줄 (`region.storageOrigin`) | `BibleDrawing.lineData` (`drawingVersion == 3`) |
/// | layout | 필사 컬럼 좌상단 | `ChapterLayout` · 소유권 판정 · reflow |
/// | content | 캔버스 content 좌상단 | `PKCanvasView.drawing` — layout 좌표 + `columnOrigin` |
///
/// `columnOrigin` 의 값은 호스팅이 실측(또는 계산)해 Feature 가 보관만 하고(§5 rev.15), 적용은 여기서만 한다.
struct DrawingCodec: Sendable {
    private let resolver = StrokeOwnershipResolver()
    private let reflow = LineBandReflow()

    init() { }

    // MARK: 합성 (§6-4)

    /// 절별 대표 행을 현재 레이아웃에 배치해 캔버스 하나로 합성한다.
    ///
    /// - `drawingVersion == 3` + metadata: `LineBandReflow` 로 현재 밑줄에 재배치 (§9).
    /// - 그 밖(legacy · v2): **무변환으로 현재 `writingRect` 원점에 배치** (§14 13). 지금 N-Canvas 가 보여 주는 것과
    ///   정확히 같다 — 각 절 캔버스가 `writingRect` 에 놓이고 `lineData` 를 로컬 좌표로 그리기 때문이다.
    ///   1절의 상단 여백 25pt 가 `writingRect` 안(`topPadding`)에 있는 이유가 이것이다.
    /// - 소유권은 기하 판정이 아니라 **행이 속한 절**이다 (§7-3 "세션이 끊기면 DB 의 절별 그룹이 진실").
    /// - Parameters:
    ///   - snapshots: `DrawingRepository.load` 결과 (히스토리 행 포함).
    ///   - layout: 현재 장 레이아웃 (§6-2 게이트 통과 후).
    ///   - columnOrigin: layout → content 평행이동.
    /// - Returns: 합성 결과.
    func compose(snapshots: [VerseDrawingSnapshot], layout: ChapterLayout, columnOrigin: CGPoint) -> ComposedChapterDrawing {
        let representatives = snapshots.representativesByVerse()
        var strokes: [PKStroke] = []
        var map: [StrokeIdentityKey: Int] = [:]
        var mismatch: Set<Int> = []
        var legacy: Set<Int> = []
        var activeRowIDs: [Int: BibleDrawingRowID] = [:]

        for verse in representatives.keys.sorted() {
            guard let snapshot = representatives[verse] else { continue }
            activeRowIDs[verse] = snapshot.rowID
            guard let region = layout.region(verse: verse) else { continue }
            let stored = Self.decode(snapshot.lineData)
            guard !stored.strokes.isEmpty else { continue }

            let placed: PKDrawing
            if snapshot.hasVersionedLayout, let metadata = snapshot.metadata {
                let result = reflow.reflow(
                    LineBandReflow.Input(verse: verse, storedDrawing: stored, metadata: metadata),
                    into: region
                )
                if result.isLayoutMismatch { mismatch.insert(verse) }
                placed = result.displayDrawing
            } else {
                if snapshot.drawingVersion == nil || snapshot.drawingVersion == 1 { legacy.insert(verse) }
                placed = stored.transformed(using: CGAffineTransform(
                    translationX: region.writingRect.minX, y: region.writingRect.minY
                ))
            }
            let content = placed.transformed(using: Self.translation(columnOrigin))
            for stroke in content.strokes {
                map[StrokeIdentityKey(stroke: stroke)] = verse
                strokes.append(stroke)
            }
        }

        return ComposedChapterDrawing(
            data: PKDrawing(strokes: strokes).dataRepresentation(),
            ownership: OwnershipSnapshot(map: map, layoutSignature: layout.signature),
            activeRowIDs: activeRowIDs,
            layoutMismatchVerses: mismatch,
            legacyVerses: legacy
        )
    }

    // MARK: 편집 → 저장 명령 (§8-2)

    /// 편집 전후 drawing 으로 소유권을 승계하고 dirty 절의 저장 명령을 만든다.
    ///
    /// ```
    /// content → layout (−columnOrigin)
    ///   → reconcile (§7-3: IdentityKey 승계 → 겹침 → 첫 control point)
    ///   → 앵커가 캔버스 밖인 획은 캔버스 안으로 클램프해 재판정 (§7-1 미결 → ① 채택)
    ///   → dirty = (before ∪ after 절) 중 ContentSignature 집합이 달라진 절 (§7-2)
    ///   → 절별 완전한 획 집합을 첫 밑줄 원점으로 localize → replace / clear / create
    /// ```
    /// - Parameters:
    ///   - beforeData: 편집 직전 content 좌표 drawing (`editBegan` 스냅샷).
    ///   - beforeOwnership: 편집 직전 소유권.
    ///   - afterData: 편집 직후 content 좌표 drawing.
    ///   - context: 레이아웃 · `columnOrigin` · 활성 행.
    /// - Returns: 승계된 소유권과 저장 명령.
    func mutations(
        beforeData: Data,
        beforeOwnership: OwnershipSnapshot,
        afterData: Data,
        context: DrawingEditContext
    ) -> DrawingEditResult {
        let toLayout = Self.translation(CGPoint(x: -context.columnOrigin.x, y: -context.columnOrigin.y))
        let before = Self.decode(beforeData).transformed(using: toLayout)
        let after = Self.decode(afterData).transformed(using: toLayout)

        var ownership = resolver.reconcile(
            previous: beforeOwnership,
            previousDrawing: before,
            drawing: after,
            layout: context.layout
        )
        ownership = adoptUnownedStrokes(of: after, ownership: ownership, layout: context.layout)

        // §8-2 — 절별 ContentSignature 집합으로 dirty 판정. 열거는 항상 drawing.strokes (§7-2).
        let beforeSignatures = Self.signaturesByVerse(before, ownership: beforeOwnership)
        let afterSignatures = Self.signaturesByVerse(after, ownership: ownership)
        let candidates = Set(beforeSignatures.keys).union(afterSignatures.keys)
        let dirty = candidates.filter { beforeSignatures[$0, default: []] != afterSignatures[$0, default: []] }

        var mutations: [VerseDrawingMutation] = []
        var issued: [Int: BibleDrawingRowID] = [:]
        for verse in dirty.sorted() {
            guard let region = context.layout.region(verse: verse) else { continue }
            let owned = after.strokes.filter { ownership.owner(of: $0) == verse }
            let visible = owned.contains { !$0.renderBounds.isNull && !$0.renderBounds.isEmpty }

            if let rowID = context.activeRowIDs[verse] {
                if visible {
                    mutations.append(.replace(
                        verse: verse, rowID: rowID,
                        data: Self.localized(owned, origin: region.storageOrigin),
                        metadata: Self.metadata(for: region, layout: context.layout)
                    ))
                } else {
                    mutations.append(.clear(verse: verse, rowID: rowID))
                }
            } else if visible {
                // 행이 없고 잉크가 생겼다 — rowID 를 저장 전에 발급한다 (§8-7).
                let rowID = BibleDrawingRowID.issue()
                issued[verse] = rowID
                mutations.append(.create(
                    verse: verse, rowID: rowID,
                    data: Self.localized(owned, origin: region.storageOrigin),
                    metadata: Self.metadata(for: region, layout: context.layout)
                ))
            }
            // 행도 없고 잉크도 없으면(그렸다가 같은 편집 안에서 지움) 만들 것이 없다.
        }

        return DrawingEditResult(ownership: ownership, mutations: mutations, issuedRowIDs: issued)
    }

    // MARK: 내부

    /// §7-1 미결 "앵커가 캔버스 밖일 때" — **① 캔버스 안으로 클램프** 를 채택한다.
    ///
    /// B 구조에서 캔버스는 화면 전폭이라 가로로 밖에서 시작하는 획은 없고, 세로는 bounce 구간에서 음수 y 가 나올 수 있다.
    /// 소유자 없는 획은 저장에서 빠져 **유실**되므로(§7-1), 가장 가까운 `captureRect` 로 귀속시킨다.
    private func adoptUnownedStrokes(of drawing: PKDrawing, ownership: OwnershipSnapshot, layout: ChapterLayout) -> OwnershipSnapshot {
        var map = ownership.map
        let bounds = CGRect(x: 0, y: 0, width: layout.writingWidth, height: layout.totalHeight)
        for stroke in drawing.strokes {
            let key = StrokeIdentityKey(stroke: stroke)
            guard map[key] == nil, let anchor = resolver.anchorPoint(of: stroke) else { continue }
            let clamped = CGPoint(
                x: min(max(anchor.x, bounds.minX), bounds.maxX),
                y: min(max(anchor.y, bounds.minY), bounds.maxY)
            )
            if let verse = layout.verse(containing: clamped) {
                map[key] = verse
            }
        }
        return OwnershipSnapshot(map: map, layoutSignature: ownership.layoutSignature)
    }

    private static func signaturesByVerse(_ drawing: PKDrawing, ownership: OwnershipSnapshot) -> [Int: Set<StrokeContentSignature>] {
        var result: [Int: Set<StrokeContentSignature>] = [:]
        for stroke in drawing.strokes {
            guard let verse = ownership.owner(of: stroke) else { continue }
            result[verse, default: []].insert(StrokeContentSignature(stroke: stroke))
        }
        return result
    }

    /// layout 좌표의 획을 첫 밑줄 원점의 verse-local 로 옮겨 직렬화한다 (§8-2 "저장 변환은 평행이동뿐").
    private static func localized(_ strokes: [PKStroke], origin: CGPoint) -> Data {
        PKDrawing(strokes: strokes)
            .transformed(using: CGAffineTransform(translationX: -origin.x, y: -origin.y))
            .dataRepresentation()
    }

    private static func metadata(for region: VerseCanvasRegion, layout: ChapterLayout) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(region: region, layoutSignature: layout.signature)
    }

    private static func decode(_ data: Data?) -> PKDrawing {
        guard let data, !data.isEmpty, let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    private static func translation(_ point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: point.x, y: point.y)
    }
}
