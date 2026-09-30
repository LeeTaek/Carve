//
//  PencilPalatteMetricsTesting.swift
//  CarveFeatureTest
//
//  R22 — 세로 화면에서 도구 팔레트가 넘쳐 redo 가 잘리던 문제.
//  여백 단계 선택은 순수 계산이므로 UI 없이 고정한다.
//

import CoreGraphics
import Testing

@testable import CarveFeature

@Suite("도구 팔레트 폭 (R22)")
struct PencilPalatteMetricsTesting {
    /// 출고 기본값: 펜 4 · 굵기 3 · 색상 3 · undo/redo 2.
    private func fit(_ width: CGFloat) -> PencilPalatteMetrics {
        PencilPalatteMetrics.fit(
            in: width,
            penTypeCount: 4,
            lineWidthCount: 3,
            colorCount: 3
        )
    }

    private func intrinsic(_ step: (horizontal: CGFloat, divider: CGFloat)) -> CGFloat {
        PencilPalatteMetrics.intrinsicWidth(
            horizontalPadding: step.horizontal,
            dividerPadding: step.divider,
            penTypeCount: 4,
            lineWidthCount: 3,
            colorCount: 3
        )
    }

    @Test("R22 재현 — 종전 여백의 고유 폭이 보유 기기의 세로 폭을 넘는다")
    func legacyPaddingOverflowsPortrait() {
        // steps[0] 이 종전 값(16/16)이다. 이 폭이 세로에서 넘쳐 마지막 그룹인 undo/redo 가 잘렸다.
        let legacy = intrinsic(PencilPalatteMetrics.steps[0])

        #expect(legacy > 744)   // iPad mini 7세대 세로
        #expect(legacy > 834)   // iPad Air 11" 세로
        #expect(legacy < 1133)  // mini 가로 — 여기서는 들어갔기 때문에 세로에서만 보였다
    }

    @Test("세로에서는 좁은 단계를 골라 전부 들어간다")
    func portraitPicksCompactStepAndFits() {
        for portraitWidth in [744.0, 834.0] as [CGFloat] {
            let metrics = fit(portraitWidth)

            #expect(metrics.needsScroll == false)
            #expect(metrics.horizontalPadding == PencilPalatteMetrics.steps[1].horizontal)

            let used = intrinsic((metrics.horizontalPadding, metrics.dividerPadding))
            #expect(used <= portraitWidth)
        }
    }

    @Test("가로에서는 종전의 넉넉한 배치를 그대로 쓴다")
    func landscapeKeepsRoomyStep() {
        for landscapeWidth in [1133.0, 1210.0] as [CGFloat] {
            let metrics = fit(landscapeWidth)

            #expect(metrics.needsScroll == false)
            #expect(metrics.horizontalPadding == PencilPalatteMetrics.steps[0].horizontal)
            #expect(metrics.dividerPadding == PencilPalatteMetrics.steps[0].divider)
        }
    }

    @Test("가장 좁은 단계로도 모자라면 스크롤로 넘긴다 — 도구를 감추지 않는다")
    func narrowWindowScrollsInsteadOfClipping() {
        // Slide Over 같은 좁은 창.
        let metrics = fit(320)

        #expect(metrics.needsScroll)
        // 스크롤로 넘길 때도 여백은 가장 좁은 단계로 고정해 터치 영역을 지킨다.
        #expect(metrics.horizontalPadding == PencilPalatteMetrics.steps[1].horizontal)
    }

    @Test("폭을 아직 재지 못한 첫 패스에서는 넉넉한 배치를 쓴다")
    func unmeasuredWidthFallsBackToRoomyStep() {
        for unmeasured in [0.0, -1.0] as [CGFloat] {
            let metrics = fit(unmeasured)

            #expect(metrics.needsScroll == false)
            #expect(metrics.horizontalPadding == PencilPalatteMetrics.steps[0].horizontal)
        }
    }

    @Test("항목이 늘면 고유 폭도 는다")
    func intrinsicWidthGrowsWithItemCount() {
        let three = PencilPalatteMetrics.intrinsicWidth(
            horizontalPadding: 8, dividerPadding: 10,
            penTypeCount: 4, lineWidthCount: 3, colorCount: 3
        )
        let five = PencilPalatteMetrics.intrinsicWidth(
            horizontalPadding: 8, dividerPadding: 10,
            penTypeCount: 4, lineWidthCount: 3, colorCount: 5
        )

        #expect(five > three)
    }

    @Test("좁은 단계에서도 터치 영역이 무너지지 않는다")
    func compactStepKeepsTouchTargets() {
        // 폭을 줄이는 방향이라 항목이 얼마나 얇아지는지 고정해 둔다.
        // 더 좁히고 싶어지면 여기서 먼저 걸린다 — 그때는 스크롤로 넘겨야 한다.
        let compact = PencilPalatteMetrics.steps[1].horizontal
        let smallestItem = PencilPalatteMetrics.colorDot + compact * 2

        #expect(smallestItem >= 40)
        #expect(PencilPalatteMetrics.iconBox + PencilPalatteMetrics.verticalPadding * 2 >= 44)
    }
}
