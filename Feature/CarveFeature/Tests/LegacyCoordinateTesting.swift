//
//  LegacyCoordinateTesting.swift
//  FeatureCarveTest
//
//  Phase 0B — legacy 좌표계 회귀 fixture
//  단일 Canvas 설계(docs/single-canvas-design.md) D3 / §10-2 를 실측 fixture 로 고정한다.
//

import Foundation
import PencilKit
import Testing

@testable import CarveFeature

/// 실기기에서 추출한 실제 필사 blob(§18-4 D8)이 현행 PencilKit 으로 그대로 읽히는지 고정한다.
///
/// **왜 필요한가.** 1.2.0 `CombinedCanvas` 는 절대좌표로 저장했고 1.2.1 에서 롤백됐다. 그 사이에 필사한 사용자의 데이터는
/// 여전히 절대좌표다. 2.0.x 까지는 N-Canvas 의 `PKDrawing.normalizedForVerseRect(_:tolerance:)` 가 두 형식을 **추측**으로 구분했고,
/// 설계 D3 가 그 추측이 원리적으로 성립하지 않는다고 진단했다(실측 225건 중 판정이 발동하는 것 29%). 2.1 은 그 도우미를 N-Canvas 와
/// 함께 지웠다 — 단일 Canvas 는 좌표 형식을 추측하지 않고 `drawingVersion` 으로 읽는다(P3, `DrawingCodecLegacyMigrationTesting`).
///
/// 여기에는 그 판단의 전제인 **인코딩 호환성**만 남는다. 어긋나면 PencilKit 인코딩이 바뀐 것이므로 마이그레이션 판단이 필요하다.
@Suite("Legacy 좌표계 fixture")
struct LegacyCoordinateTesting {

    private static let tolerance: CGFloat = 0.5

    // MARK: - 인코딩 호환성

    @Test("추출한 실사용 blob 이 현행 PencilKit 으로 그대로 디코드된다",
          arguments: LegacyDrawingFixture.all)
    func decodesWithCurrentPencilKit(sample: LegacyDrawingFixture.Sample) throws {
        let drawing = try sample.drawing()

        #expect(drawing.strokes.count == sample.expectedStrokeCount)

        // 추출 시점 실측 bounds 와 일치해야 한다.
        // 어긋나면 PencilKit 인코딩이 바뀐 것이므로 마이그레이션 판단이 필요하다.
        let bounds = drawing.bounds
        #expect(abs(bounds.minX - sample.expectedBounds.minX) < Self.tolerance)
        #expect(abs(bounds.minY - sample.expectedBounds.minY) < Self.tolerance)
        #expect(abs(bounds.width - sample.expectedBounds.width) < Self.tolerance)
        #expect(abs(bounds.height - sample.expectedBounds.height) < Self.tolerance)
    }

    @Test("dataRepresentation 라운드트립이 획 수와 bounds 를 보존한다",
          arguments: LegacyDrawingFixture.all)
    func roundTripIsStable(sample: LegacyDrawingFixture.Sample) throws {
        let original = try sample.drawing()
        let reloaded = try PKDrawing(data: original.dataRepresentation())

        #expect(reloaded.strokes.count == original.strokes.count)
        #expect(abs(reloaded.bounds.minY - original.bounds.minY) < Self.tolerance)
        #expect(abs(reloaded.bounds.height - original.bounds.height) < Self.tolerance)
    }
}
