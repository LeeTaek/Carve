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

/// 실기기에서 추출한 실제 필사 blob(§18-4 D8)으로 legacy 좌표계 처리를 검증한다.
///
/// **왜 필요한가.** 1.2.0 `CombinedCanvas` 는 절대좌표로 저장했고 1.2.1 에서 롤백됐다.
/// 그 사이에 필사한 사용자의 데이터는 여전히 절대좌표다.
/// 현재 `PKDrawing.normalizedForVerseRect(_:tolerance:)` 가 두 형식을 **추측**으로 구분하는데,
/// 설계 D3 는 이 추측이 원리적으로 성립하지 않는다고 진단했다. 아래 테스트가 그 진단을 고정한다.
///
/// **판정식.** `strokes.first.renderBounds` 가 `rect.origin` 에서 **두 축 모두** 20pt 이내면
/// 절대좌표로 간주한다. 전체 `drawing.bounds` 가 아니라 **첫 획의 renderBounds** 임에 유의.
///
/// **실측 (추출 225 건 기준).**
/// - 판정이 발동하는 것: **66 건 (29%)**
/// - 발동하지 않는 것: **159 건 (71%)** — 절대좌표였다면 복원되지 않고 그대로 남는다
///
/// **추출 데이터의 한계.** 225 건은 전부 절 로컬 좌표다.
/// 1.2.0 배포 기간(2025-12-08 ~ 2025-12-30)에 이 기기로 필사한 기록이 0 건이기 때문이다.
/// 따라서 절대좌표 fixture 는 실데이터가 아니라 `absoluteVariant(of:verseRect:)` 로 합성한다.
/// 합성 근거는 `normalizedForVerseRect` 자신의 역변환이다.
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

    // MARK: - 판정이 발동하는 소수 사례 (29%)

    @Test("첫 획이 절 원점 근처에서 시작하면 절대좌표가 로컬로 복원된다",
          arguments: [LegacyDrawingFixture.rectAtChapterMiddle,
                      LegacyDrawingFixture.rectDeepInChapter])
    func absoluteIsRestoredWhenFirstStrokeStartsNearVerseOrigin(rect: CGRect) throws {
        let local = try LegacyDrawingFixture.detectable.drawing()
        let absolute = LegacyDrawingFixture.absoluteVariant(of: local, verseRect: rect)

        // 합성된 절대좌표는 절 위치만큼 밀려 있다.
        #expect(abs(absolute.bounds.minY - (local.bounds.minY + rect.minY)) < Self.tolerance)

        let restored = absolute.normalizedForVerseRect(rect)

        #expect(abs(restored.bounds.minX - local.bounds.minX) < Self.tolerance)
        #expect(abs(restored.bounds.minY - local.bounds.minY) < Self.tolerance)
    }

    // MARK: - D3 — 추측이 깨지는 두 지점 ★

    /// **실패 모드 1 — 절대좌표인데 탐지되지 않는다 (실데이터의 71%).**
    ///
    /// 판정은 첫 획이 절 원점에서 두 축 모두 20pt 이내에서 시작할 때만 성립한다.
    /// 실제 필기는 들여쓰기·윗줄 여백 때문에 대개 그 범위를 벗어난다.
    /// 그러면 절대좌표가 **그대로 남아** 필사가 장 저 아래에 그려진다.
    ///
    /// 조용히 실패한다는 점이 핵심이다 — 오류도, 로그도 남지 않는다.
    @Test("D3: 전형적인 필기는 절대좌표여도 탐지되지 않고 그대로 남는다",
          arguments: LegacyDrawingFixture.undetectable)
    func absoluteIsMissedForTypicalHandwriting(sample: LegacyDrawingFixture.Sample) throws {
        let local = try sample.drawing()
        let rect = LegacyDrawingFixture.rectAtChapterMiddle
        let absolute = LegacyDrawingFixture.absoluteVariant(of: local, verseRect: rect)

        let normalized = absolute.normalizedForVerseRect(rect)

        // 복원되지 않고 절대좌표 그대로다.
        #expect(abs(normalized.bounds.minX - absolute.bounds.minX) < Self.tolerance)
        #expect(abs(normalized.bounds.minY - absolute.bounds.minY) < Self.tolerance)
        // 즉 로컬로 되돌아오지 못했다.
        #expect(abs(normalized.bounds.minY - local.bounds.minY) > 1)
    }

    /// **실패 모드 2 — 장 맨 위 절에서 멀쩡한 로컬 blob 이 오인되어 밀린다.**
    ///
    /// 장 상단 절은 `rect.origin` 이 원점에 가까워, 로컬 좌표 blob 도 판정 조건을 만족한다.
    /// 그 결과 **아무 문제 없던 데이터가 `rect.origin` 만큼 이동한다.**
    ///
    /// 두 실패 모드는 방향이 반대라 tolerance 를 조정해도 동시에 해소되지 않는다.
    /// 이것이 설계 P3 가 좌표 형식을 **추측하지 말고 기록하라**고 요구하는 이유다.
    @Test("D3: 장 맨 위 절에서는 로컬 blob 이 오인되어 좌표가 밀린다")
    func localIsCorruptedAtChapterTop() throws {
        let local = try LegacyDrawingFixture.detectable.drawing()
        let rect = LegacyDrawingFixture.rectAtChapterTop

        let normalized = local.normalizedForVerseRect(rect)

        // 로컬이었는데도 절대좌표로 오인되어 rect.origin 만큼 이동했다.
        #expect(abs(normalized.bounds.minY - (local.bounds.minY - rect.minY)) < Self.tolerance)
        #expect(abs(normalized.bounds.minY - local.bounds.minY) > 1)
    }

    // MARK: - 오탐이 나지 않는 구간

    @Test("장 중간 절에서는 로컬 blob 이 건드려지지 않는다",
          arguments: LegacyDrawingFixture.all)
    func localIsLeftAloneAtChapterMiddle(sample: LegacyDrawingFixture.Sample) throws {
        let local = try sample.drawing()
        let unchanged = local.normalizedForVerseRect(LegacyDrawingFixture.rectAtChapterMiddle)

        #expect(abs(unchanged.bounds.minX - local.bounds.minX) < Self.tolerance)
        #expect(abs(unchanged.bounds.minY - local.bounds.minY) < Self.tolerance)
    }
}
