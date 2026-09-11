//
//  VerseHistoryPopover.swift
//  FeatureCarve
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 이전 필사 기록 팝오버(시안 E2) — 롱탭한 절 **아래**에 붙는다.
///
/// 이 화면의 목적은 지금 쓴 것과 이전 회차를 견주는 것이라, 시트처럼 지금 필기를 덮지 않는다. 가림막도 그 절 자리는
/// 비워 둬 현재 필기가 그대로 보인다. 아래 자리가 모자라면 절 위에 붙고, 절 위치를 모르면 화면 가운데에 띄운다.
struct VerseHistoryPopover: View {
    let store: StoreOf<VerseDrawingHistoryFeature>
    /// 필기 열이 왼쪽인지 — 팝오버를 필기 열 쪽에 둔다.
    let isLeftHanded: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    private static let width: CGFloat = 460
    private static let arrowSize = CGSize(width: 22, height: 11)
    private static let gap: CGFloat = 4
    private static let preferredHeight: CGFloat = 452

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let verse = store.anchorFrame?.offsetBy(dx: -origin.x, dy: -origin.y)
            let placement = placement(verse: verse, size: proxy.size, safeArea: proxy.safeAreaInsets)

            ZStack(alignment: .topLeading) {
                scrim(size: proxy.size, cutout: verse.map { liftedCard($0, width: proxy.size.width) })
                    .onTapGesture(perform: onDismiss)

                panel(arrowX: placement.arrowX, arrowOnTop: placement.arrowOnTop)
                    .frame(width: Self.width)
                    .frame(height: placement.height, alignment: placement.arrowOnTop ? .top : .bottom)
                    .offset(x: placement.x, y: placement.y)
                    .opacity(isShown ? 1 : 0)
                    .scaleEffect(isShown || reduceMotion ? 1 : 0.97, anchor: placement.arrowOnTop ? .top : .bottom)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                isShown = true
            }
        }
        .accessibilityAction(.escape, onDismiss)
    }

    private struct Placement {
        let x: CGFloat
        let y: CGFloat
        /// 팝오버에 줄 수 있는 최대 높이. 내용이 짧으면 그만큼만 쓴다.
        let height: CGFloat
        let arrowX: CGFloat?
        let arrowOnTop: Bool
    }

    /// 필기 열 가운데 아래 → 위 → 화면 가운데 순으로 자리를 고른다.
    private func placement(verse: CGRect?, size: CGSize, safeArea: EdgeInsets) -> Placement {
        let top = safeArea.top + CarveSpacing.medium
        let bottom = size.height - safeArea.bottom - CarveSpacing.medium
        let minX = CarveSpacing.medium
        let maxX = max(minX, size.width - CarveSpacing.medium - Self.width)

        guard let verse else {
            let height = min(Self.preferredHeight, bottom - top)
            return Placement(
                x: (size.width - Self.width) / 2,
                y: max(top, (size.height - height) / 2),
                height: height,
                arrowX: nil,
                arrowOnTop: true
            )
        }

        // 필기 열(반쪽)의 가운데를 겨눈다.
        let columnCenter = isLeftHanded ? verse.minX + verse.width / 4 : verse.maxX - verse.width / 4
        let x = min(max(columnCenter - Self.width / 2, minX), maxX)
        let arrowX = min(max(columnCenter - x, 28), Self.width - 28)

        let spaceBelow = bottom - (verse.maxY + Self.gap)
        let spaceAbove = (verse.minY - Self.gap) - top
        if spaceBelow >= 240 || spaceBelow >= spaceAbove {
            return Placement(x: x, y: verse.maxY + Self.gap, height: max(0, spaceBelow), arrowX: arrowX, arrowOnTop: true)
        }
        return Placement(x: x, y: top, height: max(0, spaceAbove), arrowX: arrowX, arrowOnTop: false)
    }

    /// 들어 올린 절 — 절 메뉴(시안 E1)와 같은 자리.
    private func liftedCard(_ verse: CGRect, width: CGFloat) -> CGRect {
        let inset = ChapterLayoutHosting.pageMargins(contentWidth: width).outer - CarveSpacing.small
        return CGRect(x: inset, y: verse.minY, width: max(0, width - inset * 2), height: verse.height)
    }

    private func scrim(size: CGSize, cutout: CGRect?) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let cutout {
                path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 16, height: 16))
            }
        }
        .fill(CarveColor.scrim, style: FillStyle(eoFill: true))
        .opacity(isShown ? 1 : 0)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func panel(arrowX: CGFloat?, arrowOnTop: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous)
        return VStack(spacing: 0) {
            if arrowOnTop { arrow(x: arrowX, pointsUp: true) }
            VerseDrawingHistoryView(store: store)
                .frame(maxHeight: Self.preferredHeight)
                .carveSurface(.opaquePanel, in: shape)
                .clipShape(shape)
            if !arrowOnTop { arrow(x: arrowX, pointsUp: false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// 절을 가리키는 작은 삼각형(시안 E2). 표면색으로 칠해 팝오버와 한 덩어리로 보이게 한다.
    @ViewBuilder
    private func arrow(x: CGFloat?, pointsUp: Bool) -> some View {
        if let x {
            ArrowShape(pointsUp: pointsUp)
                .fill(CarveColor.surface)
                .frame(width: Self.arrowSize.width, height: Self.arrowSize.height)
                .offset(x: x - Self.width / 2)
                .accessibilityHidden(true)
        }
    }

    private struct ArrowShape: Shape {
        let pointsUp: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            if pointsUp {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
            path.closeSubpath()
            return path
        }
    }
}
