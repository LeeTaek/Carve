//
//  HeaderRowLayout.swift
//  CarveFeature
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import UIComponents

/// 헤더 줄 광고의 자리 판단(시안 K2).
///
/// 제목은 늘 가운데에 두고, 광고는 서재 쪽 버튼 뒤에 고정 폭으로 둔다. 제목과 겹치지 않고 들어갈 자리가 없으면 광고를 두지 않는다.
enum HeaderAdLayout {
    /// 서재 쪽 버튼과 광고 사이. 광고가 헤더 버튼처럼 보이지 않도록 버튼 간격(4pt)보다 넓게 둔다.
    static let leadingGap: CGFloat = CarveSpacing.medium
    /// 광고와 제목 사이. 제목 버튼이 좌우 16pt 여백을 갖고 있어 작게 둔다.
    static let titleGap: CGFloat = CarveSpacing.xxSmall
    /// 광고를 둘 때 제목에 남기는 가운데 폭. 긴 성경 이름은 이 폭에 맞춰 글자를 줄인다 — 장을 넘겨도 광고 폭과 표시 여부가 바뀌지 않는다.
    static let reservedTitleWidth: CGFloat = 200

    /// 헤더 축소 진행률(0 펼침 · 1 축소)에 맞춘 광고 높이.
    static func height(collapseProgress: CGFloat) -> CGFloat {
        let progress = min(1, max(0, collapseProgress))
        let range = NativeAdMetrics.headerExpandedHeight - NativeAdMetrics.headerCompactHeight
        return NativeAdMetrics.headerExpandedHeight - range * progress
    }

    /// 가운데 제목을 둔 채 서재 쪽 버튼 뒤에 넣을 광고 폭. 가로에서 자리가 남아도 넓히지 않고, 제목까지의 사이에 들어가지 않으면 nil 이다.
    static func adWidth(rowWidth: CGFloat, leadingWidth: CGFloat) -> CGFloat? {
        let available = rowWidth / 2 - reservedTitleWidth / 2 - titleGap - leadingWidth - leadingGap
        guard available >= NativeAdMetrics.headerWidth else { return nil }
        return NativeAdMetrics.headerWidth
    }

    /// 헤더 버튼 묶음 폭(44pt 버튼 · 4pt 간격).
    static func buttonGroupWidth(_ buttonCount: Int) -> CGFloat {
        guard buttonCount > 0 else { return 0 }
        return CGFloat(buttonCount) * CarveSize.minimumHitTarget + CGFloat(buttonCount - 1) * CarveSpacing.xxSmall
    }
}

/// 헤더 한 줄 배치(시안 M · K2 · L).
///
/// - 광고가 있으면 제목은 가운데 ``HeaderAdLayout/reservedTitleWidth`` 안에 두고, 광고는 서재 쪽 버튼 뒤에 고정 폭으로 둔다.
/// - 광고가 없으면 제목은 가운데를 우선하고, 좁은 창에서 버튼과 겹치면 버튼 사이 가운데로 옮겨 줄여 그린다.
/// - 줄 높이는 버튼 · 제목으로만 정한다. 광고는 같은 중심선에 맞춰 위아래로 넘친다 — 광고가 생기거나 높이가 바뀌어도
///   버튼과 제목이 움직이지 않는다.
struct HeaderRowLayout: Layout {
    enum Role {
        case leading
        case ad
        case title
        case trailing
    }

    struct RoleKey: LayoutValueKey {
        static let defaultValue: Role = .title
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews
            .filter { $0[RoleKey.self] != .ad }
            .map { $0.sizeThatFits(.unspecified).height }
            .max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let midY = bounds.midY
        var leadingWidth: CGFloat = 0
        var titleMinX = bounds.minX
        var titleMaxX = bounds.maxX

        if let leading = subview(.leading, in: subviews) {
            let size = leading.sizeThatFits(.unspecified)
            leading.place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: ProposedViewSize(size))
            leadingWidth = size.width
            titleMinX = bounds.minX + size.width + HeaderAdLayout.titleGap
        }

        if let trailing = subview(.trailing, in: subviews) {
            let size = trailing.sizeThatFits(.unspecified)
            trailing.place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: ProposedViewSize(size))
            titleMaxX = bounds.maxX - size.width - HeaderAdLayout.titleGap
        }

        if let ad = subview(.ad, in: subviews) {
            if let width = HeaderAdLayout.adWidth(rowWidth: bounds.width, leadingWidth: leadingWidth) {
                let height = ad.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                ad.place(
                    at: CGPoint(x: bounds.minX + leadingWidth + HeaderAdLayout.leadingGap, y: midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: width, height: height)
                )
                titleMinX = bounds.midX - HeaderAdLayout.reservedTitleWidth / 2
                titleMaxX = bounds.midX + HeaderAdLayout.reservedTitleWidth / 2
            } else {
                // View 가 폭을 보고 광고를 빼지만, 판단이 한 틱 어긋나도 제목 위에 겹치지 않게 크기 없이 둔다.
                ad.place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: .zero)
            }
        }

        if let title = subview(.title, in: subviews) {
            let available = max(0, titleMaxX - titleMinX)
            let ideal = title.sizeThatFits(.unspecified)
            let width = min(ideal.width, available)
            let centeredMinX = bounds.midX - width / 2
            let fitsCentered = centeredMinX >= titleMinX && centeredMinX + width <= titleMaxX
            let minX = fitsCentered ? centeredMinX : titleMinX + (available - width) / 2
            title.place(
                at: CGPoint(x: minX, y: midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: ideal.height)
            )
        }
    }

    private func subview(_ role: Role, in subviews: Subviews) -> LayoutSubview? {
        subviews.first { $0[RoleKey.self] == role }
    }
}
