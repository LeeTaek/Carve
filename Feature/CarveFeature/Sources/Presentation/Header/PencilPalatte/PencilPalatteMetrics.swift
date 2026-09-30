//
//  PencilPalatteMetrics.swift
//  FeatureCarve
//
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

/// 도구 팔레트가 **실제 가용 폭**에 들어가도록 여백 단계를 고르는 순수 계산 (R22).
///
/// 종전에는 네 그룹에 각각 `.frame(maxWidth: .infinity)` 를 주고 항목마다 기본 `.padding()`(16pt)
/// 을 붙였다. 고유 폭이 **937pt** 라서 iPad mini 세로(744pt) · Air 11" 세로(834pt) 에서 넘쳤고,
/// 마지막 그룹인 undo/redo 가 잘렸다. 화면 크기를 참조하는 코드는 없었고 원인은 누적 고유 폭이다.
///
/// 여기서는 넉넉한 단계부터 시도해 **들어가는 가장 넉넉한 단계**를 고른다. 가장 좁은 단계로도
/// 모자라면 `needsScroll` 을 세워 가로 스크롤로 넘긴다 — 어떤 폭에서도 도구를 감추지 않는다.
struct PencilPalatteMetrics: Equatable {
    /// 항목 좌우 여백.
    let horizontalPadding: CGFloat
    /// 구분선 좌우 여백.
    let dividerPadding: CGFloat
    /// 가장 좁은 단계로도 모자라 가로 스크롤이 필요한가.
    let needsScroll: Bool

    /// 아이콘 버튼 한 변 (펜 종류 · 선 굵기 · undo/redo).
    static let iconBox: CGFloat = 35
    /// 색상 원 지름.
    static let colorDot: CGFloat = 25
    /// 항목 사이 간격.
    static let itemSpacing: CGFloat = 8
    /// 항목 상하 여백. 터치 영역 확보용이라 폭과 무관하게 고정한다.
    static let verticalPadding: CGFloat = 6
    /// 그룹 사이 구분선 개수.
    static let dividerCount: Int = 3

    /// 넉넉한 순서. 첫 번째가 종전 값이라 가로 화면의 모양은 그대로 유지된다.
    static let steps: [(horizontal: CGFloat, divider: CGFloat)] = [
        (16, 16),
        (8, 10)
    ]

    /// 주어진 여백에서 팔레트가 차지하는 고유 폭.
    ///
    /// - Parameters:
    ///   - penTypeCount: 펜 종류 버튼 수.
    ///   - lineWidthCount: 선 굵기 버튼 수.
    ///   - colorCount: 색상 버튼 수.
    ///   - undoRedoCount: undo/redo 버튼 수.
    static func intrinsicWidth(
        horizontalPadding: CGFloat,
        dividerPadding: CGFloat,
        penTypeCount: Int,
        lineWidthCount: Int,
        colorCount: Int,
        undoRedoCount: Int = 2
    ) -> CGFloat {
        func group(_ itemCount: Int, itemWidth: CGFloat) -> CGFloat {
            guard itemCount >= 1 else { return 0 }
            let items = CGFloat(itemCount) * (itemWidth + horizontalPadding * 2)
            let gaps = CGFloat(itemCount - 1) * itemSpacing
            return items + gaps
        }

        let boxGroups = group(penTypeCount, itemWidth: iconBox)
            + group(lineWidthCount, itemWidth: iconBox)
            + group(undoRedoCount, itemWidth: iconBox)
        let colors = group(colorCount, itemWidth: colorDot)
        let dividers = CGFloat(dividerCount) * (1 + dividerPadding * 2)

        return boxGroups + colors + dividers
    }

    /// 가용 폭에 들어가는 가장 넉넉한 단계를 고른다.
    ///
    /// - Parameter availableWidth: 팔레트가 쓸 수 있는 폭. 아직 측정되지 않아 `0` 이하면
    ///   가장 넉넉한 단계를 그대로 쓴다 (첫 레이아웃 패스에서 좁게 깜빡이지 않게).
    static func fit(
        in availableWidth: CGFloat,
        penTypeCount: Int,
        lineWidthCount: Int,
        colorCount: Int,
        undoRedoCount: Int = 2
    ) -> PencilPalatteMetrics {
        guard availableWidth > 0 else {
            return .init(
                horizontalPadding: steps[0].horizontal,
                dividerPadding: steps[0].divider,
                needsScroll: false
            )
        }

        for step in steps {
            let width = intrinsicWidth(
                horizontalPadding: step.horizontal,
                dividerPadding: step.divider,
                penTypeCount: penTypeCount,
                lineWidthCount: lineWidthCount,
                colorCount: colorCount,
                undoRedoCount: undoRedoCount
            )
            if width <= availableWidth {
                return .init(
                    horizontalPadding: step.horizontal,
                    dividerPadding: step.divider,
                    needsScroll: false
                )
            }
        }

        // 가장 좁은 단계로도 모자란다. 축소를 더 밀어붙이면 터치 영역이 무너지므로 스크롤로 넘긴다.
        let narrowest = steps.last ?? (horizontal: 8, divider: 10)
        return .init(
            horizontalPadding: narrowest.horizontal,
            dividerPadding: narrowest.divider,
            needsScroll: true
        )
    }
}
