//
//  LegacyInkPlacementTesting.swift
//  CarveFeatureTest
//
//  D9 실기기 — legacy 잉크가 엉뚱한 자리에 그려진다는 관측의 좌표 근거를 고정한다.
//
//  세 가지를 서로 다른 질문으로 나눠 고정한다.
//  ① 합성 좌표가 `columnOrigin` 을 실제로 따라가는가 (회전 = 필사 폭·컬럼 원점 A/B)
//  ② 승격(`replace`, §10-2 정책 5)이 **표시 위치를 그대로 굳히는가** — 표시가 틀리면 저장도 틀린다
//  ③ `drawingVersion == 3` 인데 metadata 가 없는 행의 원점 (§10-1 "좌표 형식의 단일 진실은 버전이다")
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

@Suite("D9 — legacy 잉크 좌표")
struct LegacyInkPlacementTesting {
    private let codec = DrawingCodec()

    /// D9 실기기(iPad mini A17 Pro, 오른손) 실측값. 방향이 바뀌면 필사 폭과 컬럼 원점이 함께 움직인다.
    private static let portraitWidth: CGFloat = 372.00
    private static let landscapeWidth: CGFloat = 566.50
    private static let portraitColumnX: CGFloat = 366.70
    private static let landscapeColumnX: CGFloat = 556.34
    /// 부동소수 왕복 허용치. 좌표 논증은 pt 단위라 이 정도면 충분히 엄격하다.
    private static let epsilon: CGFloat = 0.01

    // MARK: 헬퍼

    /// 절마다 한 줄(30pt)인 균일 레이아웃. verse v 의 `writingRect.minY = (v−1)×30`, `storageOrigin.y = v×30`,
    /// 그리고 **`writingRect.minX` 는 폭과 무관하게 언제나 0** 이다 (`ChapterLayoutBuilder` 의 배치 규칙).
    private func layout(width: CGFloat) -> ChapterLayout {
        OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30, writingWidth: width)
    }

    private func data(_ strokes: [PKStroke]) -> Data {
        PKDrawing(strokes: strokes).dataRepresentation()
    }

    private func stroke(_ from: CGPoint, _ to: CGPoint, seed: UInt32, time: TimeInterval = 1_000) -> PKStroke {
        OwnershipTestSupport.stroke(from: from, to: to, seed: seed, creationTime: time)
    }

    /// 각 획의 첫 control point 를 캔버스 좌표로 옮긴 값 — 소유권·band 판정이 쓰는 앵커와 같은 점이다.
    private func anchors(_ blob: Data) throws -> [CGPoint] {
        try PKDrawing(data: blob).strokes.compactMap { stroke in
            stroke.path.first.map { $0.location.applying(stroke.transform) }
        }
    }

    private func snapshot(
        verse: Int,
        strokes: [PKStroke],
        rowKey: String,
        version: Int?,
        metadata: DrawingLayoutMetadata? = nil
    ) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowKey), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1), lineData: data(strokes),
            drawingVersion: version, metadata: metadata
        )
    }

    // MARK: ① 회전 — 합성 좌표는 columnOrigin 을 반드시 따라간다

    @Test("legacy(v1) 잉크의 content x = 저장 x + columnOrigin.x — 방향이 바뀌면 정확히 Δ 만큼 움직인다")
    func legacyInkFollowsColumnOrigin() throws {
        let local = stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 21)
        let row = snapshot(verse: 2, strokes: [local], rowKey: "legacy-2", version: 1)

        let portrait = codec.compose(
            snapshots: [row], layout: layout(width: Self.portraitWidth),
            columnOrigin: CGPoint(x: Self.portraitColumnX, y: 0)
        )
        let landscape = codec.compose(
            snapshots: [row], layout: layout(width: Self.landscapeWidth),
            columnOrigin: CGPoint(x: Self.landscapeColumnX, y: 0)
        )
        #expect(portrait.legacyVerses == [2])
        #expect(landscape.legacyVerses == [2])

        let portraitX = try #require(anchors(portrait.data).first).x
        let landscapeX = try #require(anchors(landscape.data).first).x

        // `writingRect.minX` 는 항상 0 이므로 x 에 기여하는 것은 columnOrigin 뿐이다.
        #expect(abs(portraitX - (10 + Self.portraitColumnX)) < Self.epsilon)
        #expect(abs(landscapeX - (10 + Self.landscapeColumnX)) < Self.epsilon)
        // ★ D9 관측의 반례 — 같은 blob 이 두 방향에서 같은 content x 에 놓일 수는 없다.
        #expect(abs((landscapeX - portraitX) - (Self.landscapeColumnX - Self.portraitColumnX)) < Self.epsilon)
        // 저장 x 가 0 이상인 한 잉크는 컬럼 왼쪽(본문 텍스트 위)으로 나가지 않는다.
        #expect(portraitX >= Self.portraitColumnX)
        #expect(landscapeX >= Self.landscapeColumnX)
    }

    @Test("저장 x 가 음수면 그만큼 컬럼 왼쪽으로 나간다 — 두 방향 모두에서 나간다")
    func negativeStoredXLeavesColumnInBothOrientations() throws {
        // 컬럼 원점보다 왼쪽에서 시작하는 저장 좌표. 1.2.0 절대좌표 회귀(§10-2)처럼 좌표계가 다른 blob 의 모형이다.
        let local = stroke(CGPoint(x: -185.34, y: 5), CGPoint(x: -100, y: 5), seed: 25)
        let row = snapshot(verse: 2, strokes: [local], rowKey: "legacy-neg", version: 1)

        let portraitX = try #require(anchors(codec.compose(
            snapshots: [row], layout: layout(width: Self.portraitWidth),
            columnOrigin: CGPoint(x: Self.portraitColumnX, y: 0)
        ).data).first).x
        let landscapeX = try #require(anchors(codec.compose(
            snapshots: [row], layout: layout(width: Self.landscapeWidth),
            columnOrigin: CGPoint(x: Self.landscapeColumnX, y: 0)
        ).data).first).x

        // 세로에서도 이미 컬럼 밖이다 — "세로는 멀쩡하고 가로만 틀리다" 는 저장 좌표만으로 설명되지 않는다.
        #expect(portraitX < Self.portraitColumnX)
        #expect(landscapeX < Self.landscapeColumnX)
        #expect(abs((landscapeX - portraitX) - (Self.landscapeColumnX - Self.portraitColumnX)) < Self.epsilon)
    }

    // MARK: ② 승격 — 표시 위치가 그대로 저장에 굳는다

    @Test("승격(replace)은 legacy 잉크의 표시 위치를 그대로 굳힌다 — 표시가 틀렸으면 저장도 같이 틀어진다")
    func promotionFreezesDisplayedPosition() throws {
        let stored = stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 22)
        let origin = CGPoint(x: 100, y: 0)
        let current = layout(width: 320)
        let composed = codec.compose(
            snapshots: [snapshot(verse: 2, strokes: [stored], rowKey: "legacy-2", version: 1)],
            layout: current, columnOrigin: origin
        )
        #expect(composed.legacyVerses == [2])
        let displayed = try #require(anchors(composed.data).first)
        #expect(displayed == CGPoint(x: 110, y: 35))

        // 그 절에 새 획 하나 — §10-2 정책 5 의 승격 조건이다.
        let added = stroke(CGPoint(x: 140, y: 35), CGPoint(x: 150, y: 35), seed: 23)
        var after = try PKDrawing(data: composed.data).strokes
        after.append(added)
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership, afterData: data(after),
            context: DrawingEditContext(layout: current, columnOrigin: origin, activeRowIDs: composed.activeRowIDs)
        )
        #expect(result.mutations.count == 1)
        guard case .replace(let verse, let rowID, let saved, let metadata) = try #require(result.mutations.first) else {
            Issue.record("replace 가 아니다")
            return
        }
        #expect(verse == 2)
        #expect(rowID.raw == "legacy-2")
        // x 는 손대지 않는다 — `storageOrigin.x == writingRect.minX == 0`. y 만 첫 밑줄 기준으로 내려간다.
        #expect(try anchors(saved).contains(CGPoint(x: 10, y: -25)))

        // 승격된 행을 다시 합성하면 옛 획이 **정확히 같은 자리**로 돌아온다.
        // 즉 승격은 어긋난 자리를 고쳐 주지 않고, 어긋난 자리 그대로 v3 로 굳힌다.
        let promoted = VerseDrawingSnapshot(
            verse: 2, rowID: rowID, isPresent: true, updateDate: Date(timeIntervalSince1970: 2),
            lineData: saved, drawingVersion: 3, metadata: metadata
        )
        let recomposed = codec.compose(snapshots: [promoted], layout: current, columnOrigin: origin)
        #expect(recomposed.legacyVerses.isEmpty)
        #expect(try anchors(recomposed.data).contains(displayed))
    }

    // MARK: ③ drawingVersion 3 + metadata 없음

    @Test("drawingVersion 3 인데 metadata 가 없는 행은 첫 밑줄 원점으로 읽는다 (§10-1 · §9-3-1)")
    func versionThreeWithoutMetadataIsPlacedAtFirstUnderline() throws {
        // v3 좌표계는 **첫 밑줄 원점**이다. 첫 밑줄 5pt 아래에 그은 획.
        let stored = stroke(CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), seed: 24)
        let origin = CGPoint(x: 100, y: 0)
        let current = layout(width: 320)
        let composed = codec.compose(
            snapshots: [snapshot(verse: 2, strokes: [stored], rowKey: "v3-nometa", version: 3, metadata: nil)],
            layout: current, columnOrigin: origin
        )

        // verse 2 의 첫 밑줄 = storageOrigin (0, 60) → content (100, 60). 그 5pt 아래.
        // `writingRect` 원점(v2 의미, content y 30)으로 놓으면 첫 밑줄만큼 위로 밀린다.
        #expect(try anchors(composed.data) == [CGPoint(x: 110, y: 65)])
        // legacy 가 아니다 — 좌표 형식은 확정돼 있고 band 매핑 근거만 없다. 통짜 보존 + mismatch 기록 (§9-3-1).
        #expect(composed.legacyVerses.isEmpty)
        #expect(composed.layoutMismatchVerses == [2])
    }
}
