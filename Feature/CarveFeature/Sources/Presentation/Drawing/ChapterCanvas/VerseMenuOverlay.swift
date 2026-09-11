//
//  VerseMenuOverlay.swift
//  FeatureCarve
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import UIComponents

/// 절 롱탭 메뉴(시안 E1) — 가림막 · 들어 올린 절 · 메뉴 카드.
///
/// 가림막은 롱탭한 절 행만 비워 두어 그 절이 떠 보이게 한다. 메뉴는 절 아래에 두고, 자리가 없으면 위, 그래도 없으면
/// 누른 지점 가까이에 둔다. 좌표는 창 좌표로 받아 이 뷰의 전역 원점을 빼서 쓴다.
///
/// 항목은 할 수 있을 때만 둔다(UI-2) — 「이전 필사 내용 보기」 는 지난 회차가 있을 때, 「지우기」 는 획이 있을 때.
/// 「이미지 저장」 · 「위젯에 표시」 는 기능이 붙기 전까지 **비활성**으로 보인다.
struct VerseMenuOverlay: View {
    let menu: ChapterCanvasVerseMenu
    let onHistory: () -> Void
    let onErase: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    private static let menuWidth: CGFloat = 320
    private static let rowHeight: CGFloat = 52
    private static let gap: CGFloat = CarveSpacing.medium
    private static let cornerRadius: CGFloat = 16

    private enum Item: CaseIterable {
        case history, image, widget, erase
    }

    private var items: [Item] {
        Item.allCases.filter { item in
            switch item {
            case .history: menu.availability.canViewHistory
            case .erase: menu.availability.canErase
            case .image, .widget: true
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let card = liftedCard(in: proxy.size, origin: origin)
            let menuFrame = menuFrame(below: card, in: proxy.size, safeArea: proxy.safeAreaInsets, origin: origin)

            ZStack(alignment: .topLeading) {
                scrim(size: proxy.size, cutout: card)
                    .onTapGesture(perform: onDismiss)

                menuCard
                    .frame(width: menuFrame.width)
                    .offset(x: menuFrame.minX, y: menuFrame.minY)
                    .scaleEffect(isShown || reduceMotion ? 1 : 0.96, anchor: .top)
                    .opacity(isShown ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
                isShown = true
            }
        }
        .accessibilityAction(.escape, onDismiss)
    }

    /// 들어 올린 절 — 행 전체에서 종이 여백만큼 안쪽(시안: 1180pt 화면에서 좌우 32pt).
    private func liftedCard(in size: CGSize, origin: CGPoint) -> CGRect {
        let frame = menu.verseFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        let inset = ChapterLayoutHosting.pageMargins(contentWidth: size.width).outer - CarveSpacing.small
        return CGRect(x: inset, y: frame.minY, width: max(0, size.width - inset * 2), height: frame.height)
    }

    /// 메뉴 자리 — 절 아래 → 절 위 → 누른 지점 순으로 들어가는 곳.
    private func menuFrame(below card: CGRect, in size: CGSize, safeArea: EdgeInsets, origin: CGPoint) -> CGRect {
        let height = CGFloat(items.count) * Self.rowHeight
        let anchor = CGPoint(x: menu.anchor.x - origin.x, y: menu.anchor.y - origin.y)
        let minX = CarveSpacing.medium
        let maxX = max(minX, size.width - CarveSpacing.medium - Self.menuWidth)
        let x = min(max(anchor.x - Self.menuWidth / 2, minX), maxX)

        let top = safeArea.top + CarveSpacing.medium
        let bottom = size.height - safeArea.bottom - CarveSpacing.medium
        let y: CGFloat
        if card.maxY + Self.gap + height <= bottom {
            y = card.maxY + Self.gap
        } else if card.minY - Self.gap - height >= top {
            y = card.minY - Self.gap - height
        } else {
            y = min(max(anchor.y + Self.gap, top), max(top, bottom - height))
        }
        return CGRect(x: x, y: y, width: Self.menuWidth, height: height)
    }

    /// 가림막 — 들어 올린 절 자리만 비운다(even-odd).
    private func scrim(size: CGSize, cutout: CGRect) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRoundedRect(in: cutout, cornerSize: CGSize(width: Self.cornerRadius, height: Self.cornerRadius))
        }
        .fill(CarveColor.scrim, style: FillStyle(eoFill: true))
        .opacity(isShown ? 1 : 0)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 { CarveDivider() }
                row(item)
            }
        }
        .carveSurface(.panel, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ item: Item) -> some View {
        let isEnabled = item == .history || item == .erase
        let color = item == .erase ? CarveColor.danger : CarveColor.ink
        return Button {
            switch item {
            case .history: onHistory()
            case .erase: onErase()
            case .image, .widget: break
            }
        } label: {
            HStack(spacing: CarveSpacing.medium) {
                icon(item).image
                title(item)
                    .font(CarveTypography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? color : CarveColor.ink.opacity(0.35))
            .padding(.horizontal, CarveSpacing.medium + CarveSpacing.xxSmall)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHint(isEnabled ? "" : "준비 중인 기능이에요")
    }

    private func icon(_ item: Item) -> CarveIcon {
        switch item {
        case .history: .history
        case .image: .photo
        case .widget: .widget
        case .erase: .trash
        }
    }

    private func title(_ item: Item) -> Text {
        switch item {
        case .history: Text("이전 필사 내용 보기")
        case .image: Text("이미지 저장")
        case .widget: Text("위젯에 표시")
        case .erase: Text("지우기")
        }
    }
}
