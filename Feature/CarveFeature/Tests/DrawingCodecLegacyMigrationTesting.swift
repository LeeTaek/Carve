//
//  DrawingCodecLegacyMigrationTesting.swift
//  CarveFeatureTest
//
//  1.3.0(V3) 필사를 2.0.0 단일 Canvas 가 어떻게 놓는가 — legacy 좌표 규약 (§14 13 · §10-2)
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

@testable import CarveFeature

/// 1.3.0 에서 올라온 필사가 **유실 없이 제자리에** 놓이는지 고정한다.
///
/// 스키마 층(행·필드가 V3 → V4 → V5 마이그레이션에서 살아남는가)은 `DrawingSchemaV4MigrationTesting` 이
/// 따로 본다. 이 파일은 그 위층 — 살아남은 행의 **좌표**를 다룬다.
///
/// legacy(`drawingVersion` nil/1)의 규약은 **무변환으로 현재 `writingRect` 원점에 배치**다 (§14 13).
/// 좌표 형식을 추측하지 않는다는 뜻이며(P3), 그래서 절 로컬 blob 은 제자리에 놓이고
/// 1.2.0 이 남긴 절대좌표 blob 은 밀린 채 놓인다. 두 결과를 모두 수치로 적어 둔다.
@Suite("legacy 좌표 — 1.3.0 필사의 단일 Canvas 배치")
struct DrawingCodecLegacyMigrationTesting {
    private let codec = DrawingCodec()
    /// 4절 · 줄 30pt · 폭 320. verse v 의 writingRect.origin = (0, (v−1)×30).
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
    private let columnOrigin = CGPoint(x: 100, y: 0)
    /// 실측 상수와 비교할 때의 허용 오차. `LegacyCoordinateTesting` 과 같은 값이다.
    private static let tolerance: CGFloat = 0.5

    private func legacySnapshot(verse: Int, strokes: [PKStroke], rowKey: String) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowKey), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1),
            lineData: PKDrawing(strokes: strokes).dataRepresentation(), drawingVersion: 1, metadata: nil
        )
    }

    private func context(active: [Int: BibleDrawingRowID]) -> DrawingEditContext {
        DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: active)
    }

    /// 실사용 blob 이 **캔버스의 어느 좌표에 놓이는지**를 절대 수치로 못 박는다.
    ///
    /// `DrawingCodecTesting` 의 "1.3.0의 여러 절 필사…" 는 기대 위치를 구현과 같은 변환식으로 계산한다.
    /// 그 식이 바뀌면 기대값도 함께 움직여 회귀를 놓치므로, 여기서는 fixture 실측 bounds 와
    /// 레이아웃 상수만으로 답을 미리 적어 둔다.
    @Test("legacy 실사용 blob 은 실측 bounds 그대로 절의 writingRect 원점에 놓인다 — 절대 좌표 고정")
    func legacyFixtureLandsAtFixedCanvasCoordinates() throws {
        let sample = LegacyDrawingFixture.multiLine
        let composed = codec.compose(
            snapshots: [legacySnapshot(verse: 3, strokes: try sample.drawing().strokes, rowKey: "fixture-3")],
            layout: layout, columnOrigin: columnOrigin
        )
        let displayed = try PKDrawing(data: composed.data)

        // writingRect(verse 3).origin (0, 60) + columnOrigin (100, 0) + 실측 bounds.origin (21, 30).
        #expect(displayed.strokes.count == sample.expectedStrokeCount)
        #expect(abs(displayed.bounds.minX - 121) < Self.tolerance)
        #expect(abs(displayed.bounds.minY - 90) < Self.tolerance)
        #expect(abs(displayed.bounds.width - sample.expectedBounds.width) < Self.tolerance)
        #expect(abs(displayed.bounds.height - sample.expectedBounds.height) < Self.tolerance)
    }

    /// 절 원점 **위로** 벗어나는 실데이터(`aboveOrigin`, 실측 `minY == -3`).
    ///
    /// legacy 는 무변환 배치라 이런 획은 현재 `writingRect` 위로 나가 **바로 위 절의 영역을 침범**한다.
    /// 보이는 위치가 겹치는 것 자체는 1.3.0 에서도 마찬가지였으므로 결함이 아니다. 문제가 되는 것은
    /// **소유권이 위 절로 넘어가는 경우**다 — 그러면 다음 저장에서 필사가 다른 절 행에 옮겨 붙는다.
    @Test("절 원점 위로 삐져나간 legacy 획은 위 절 영역을 침범해도 소유권은 행의 절을 유지한다")
    func legacyInkAboveVerseOriginKeepsItsRowVerse() throws {
        let sample = LegacyDrawingFixture.aboveOrigin
        let composed = codec.compose(
            snapshots: [legacySnapshot(verse: 3, strokes: try sample.drawing().strokes, rowKey: "above-3")],
            layout: layout, columnOrigin: columnOrigin
        )
        let displayed = try PKDrawing(data: composed.data)

        // writingRect(verse 3).origin.y 60 + 실측 minY (−3) = 57 — 절 2 의 writingRect 안이다.
        #expect(abs(displayed.bounds.minY - 57) < Self.tolerance)
        let aboveVerse = try #require(layout.region(verse: 2))
        #expect(displayed.bounds.minY < aboveVerse.writingRect.maxY + columnOrigin.y)

        // 그럼에도 모든 획의 소유권과 저장 대상 행은 3 이어야 한다.
        #expect(displayed.strokes.count == sample.expectedStrokeCount)
        for stroke in displayed.strokes {
            #expect(composed.ownership.owner(of: stroke) == 3)
        }
        #expect(composed.activeRowIDs.keys.sorted() == [3])

        let unchanged = codec.mutations(
            beforeData: composed.data,
            beforeOwnership: composed.ownership,
            afterData: displayed.dataRepresentation(),
            context: context(active: composed.activeRowIDs)
        )
        #expect(unchanged.mutations.isEmpty)
    }

    /// **알려진 한계 — 1.2.0 `CombinedCanvas` 가 남긴 절대좌표 blob.**
    ///
    /// 단일 Canvas 는 legacy(`drawingVersion` nil/1)를 **무조건 절 로컬로 보고 무변환 배치**한다 (§14 13).
    /// 좌표 형식을 추측하지 않는다는 뜻이므로(P3), 절대좌표로 저장됐던 blob 은 원래 절 rect 만큼 밀린 채 놓인다.
    /// `normalizedForVerseRect` 의 추측 복원은 이 경로에 **없다** — 실데이터의 71% 를 놓치고 장 상단에서는
    /// 오히려 멀쩡한 로컬을 망가뜨리기 때문이다 (`LegacyCoordinateTesting` D3).
    ///
    /// 그러므로 이 테스트의 통과는 "안전하다" 가 아니라 **밀림의 크기를 고정했다**는 뜻이다. 함께 확인하는
    /// `legacyInkBounds` 가 이 사실을 신고하는 유일한 근거이며, 사용자 안내·복구는 COMPAT-1 의 몫이다.
    @Test("1.2.0 절대좌표 blob 은 보정되지 않고 원래 절 rect 만큼 밀린 채 놓인다 (D3 · §14 13)")
    func absoluteLegacyBlobStaysShiftedByItsOriginalVerseRect() throws {
        let sample = LegacyDrawingFixture.multiLine
        // 시편 119편처럼 장 깊숙한 절에서 저장됐던 경우 (384, 5200).
        let originalRect = LegacyDrawingFixture.rectDeepInChapter
        let absolute = LegacyDrawingFixture.absoluteVariant(of: try sample.drawing(), verseRect: originalRect)

        let composed = codec.compose(
            snapshots: [legacySnapshot(verse: 2, strokes: absolute.strokes, rowKey: "abs-2")],
            layout: layout, columnOrigin: columnOrigin
        )
        let displayed = try PKDrawing(data: composed.data)

        // 로컬이었다면 (121, 60) 에 놓였을 잉크가 originalRect.origin 만큼 더 밀린다.
        #expect(abs(displayed.bounds.minX - (121 + originalRect.minX)) < Self.tolerance)
        #expect(abs(displayed.bounds.minY - (60 + originalRect.minY)) < Self.tolerance)

        // 장 전체(4절)보다 훨씬 아래다 — 화면에서는 필사가 사라진 것처럼 보인다.
        let lastVerse = try #require(layout.region(verse: 4))
        #expect(displayed.bounds.minY > lastVerse.writingRect.maxY + columnOrigin.y)

        // 이 사고를 밖에서 알아챌 수 있는 유일한 값이다.
        #expect(composed.legacyVerses == [2])
        let inkBounds = try #require(composed.legacyInkBounds)
        #expect(abs(inkBounds.minY - displayed.bounds.minY) < Self.tolerance)
    }
}
