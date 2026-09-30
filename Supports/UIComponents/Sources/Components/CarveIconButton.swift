//
//  CarveIconButton.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 44pt 정사각 아이콘 버튼(시안 M · L 헤더, C 팔레트).
///
/// 선택 상태는 Feature 의 `State` 에 두고 ``init(_:accessibilityLabel:isSelected:background:action:)`` 의
/// `isSelected` 로 넘긴다. 탭은 콜백으로 받아 `Action` 을 보낸다 — 컴포넌트마다 Reducer 를 두지 않는다.
/// 비활성은 `.disabled(_:)` 로 준다(VoiceOver 가 흐리게 표시됨으로 읽는다).
///
/// 눌림 · 선택은 색만이 아니라 바탕과 테두리도 바뀐다(`header-icons.svg` 상태 셋).
public struct CarveIconButton: View {
    /// 버튼 바탕.
    public enum Background: Sendable {
        /// 종이 위에 떠 있는 버튼 — 헤더. 자기 표면(iOS 26 이상 유리)을 갖는다.
        case floating
        /// 이미 표면 안에 있는 버튼 — 도구 팔레트. 눌리거나 선택했을 때만 바탕이 생긴다.
        case plain
    }

    private let icon: CarveIcon
    private let accessibilityLabel: String
    private let isSelected: Bool
    private let background: Background
    private let visualScale: CGFloat
    private let action: () -> Void

    /// - Parameters:
    ///   - icon: 그릴 아이콘.
    ///   - accessibilityLabel: VoiceOver 이름. 아이콘만 두는 버튼이라 반드시 준다(예: 「본문 설정」).
    ///   - isSelected: 선택 · 열림 상태(예: 팝오버가 열린 본문 설정 버튼).
    ///   - background: 버튼 바탕.
    ///   - visualScale: 아이콘과 표면의 크기. 탭 영역은 항상 44pt로 유지한다.
    ///   - action: 탭 콜백.
    public init(
        _ icon: CarveIcon,
        accessibilityLabel: String,
        isSelected: Bool = false,
        background: Background = .floating,
        visualScale: CGFloat = 1,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
        self.background = background
        self.visualScale = visualScale
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon.image
        }
        .buttonStyle(
            CarveIconButtonStyle(
                isSelected: isSelected,
                background: background,
                visualScale: visualScale
            )
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 떠 있는 아이콘 버튼을 가리키는 작은 표식. 안내 문장에서 「이 버튼」 을 보여 줄 때 쓰고, 누를 수 없다.
///
/// ``CarveIconButton`` 의 `floating` 과 같은 모서리 비율로 그리고, 한 변은 캡션 한 줄에 들어가는 크기다.
/// 그림은 헤더(24/44)보다 크게 넣어 둘레 글자 높이와 맞춘다. 무엇인지는 둘레 문장이 말하므로 VoiceOver 에서는 숨긴다.
///
/// ⚠️ 유리를 그대로 쓰지 않는다. 유리 패널(설정) 안에서는 유리가 바탕보다 어두운 납작한 회색으로 그려져,
///    종이 위 헤더 버튼(밝은 면 · 옅은 그림자)과 달라 보였다(iOS 26.2, 2026-09-30). 유리를 쓰는 조건에서는 그 모습을
///    직접 칠하고, 헤더도 불투명해지는 조건(iOS 26 미만 · 투명도 줄이기 · 대비 늘리기)에서는 헤더와 같은 표면을 쓴다.
public struct CarveIconBadge: View {
    /// 한 변의 기본값(캡션 기준). ``CarveIconBadgeParagraph`` 가 표식 자리를 비울 때도 쓴다.
    static let baseSide: CGFloat = 20

    private let icon: CarveIcon
    /// 한 변. 캡션 글자와 함께 커진다.
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = CarveIconBadge.baseSide

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(_ icon: CarveIcon) {
        self.icon = icon
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CarveRadius.control * side / CarveSize.minimumHitTarget, style: .continuous)
        let glyph = icon.image
            .resizable()
            .frame(width: side * 0.7, height: side * 0.7)
            .foregroundStyle(CarveColor.ink)
            .frame(width: side, height: side)

        Group {
            if #available(iOS 26.0, *), allowsGlass(reduceTransparency: reduceTransparency, contrast: contrast) {
                glyph
                    .background(colorScheme == .dark ? CarveColor.surface : CarveColor.canvas, in: shape)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: 2, y: 1)
            } else {
                glyph.carveSurface(.floatingControl, in: shape)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 버튼 표식으로 시작하는 문단. 표식 뒤로 첫 줄이 이어지고, 둘째 줄부터는 표식 아래 왼쪽 끝에서 시작한다.
///
/// `Text` 안에는 뷰를 넣을 수 없어, 첫 줄 앞에 표식 폭만큼 빈 자리를 두고 그 자리에 표식을 겹친다.
/// 표식은 첫 줄 한글 가운데에 맞추고, 위아래로 넘치는 만큼 줄 간격을 조금 띄운다. 글꼴 · 색 · 접근성 이름은 부르는 쪽에서 준다.
public struct CarveIconBadgeParagraph: View {
    private let icon: CarveIcon
    private let text: Text
    /// 표식 한 변. ``CarveIconBadge`` 와 같은 값 · 같은 기준으로 커진다.
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = CarveIconBadge.baseSide
    /// 기준선에서 한글 가운데까지의 높이.
    @ScaledMetric(relativeTo: .caption) private var midline: CGFloat = 4

    public init(_ icon: CarveIcon, text: Text) {
        self.icon = icon
        self.text = text
    }

    public var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            Text("\(Image(size: CGSize(width: side + CarveSpacing.xxSmall, height: 1)) { _ in })\(text)")
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            CarveIconBadge(icon)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + midline }
        }
    }
}

private struct CarveIconButtonStyle: ButtonStyle {
    let isSelected: Bool
    let background: CarveIconButton.Background
    let visualScale: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let scale = min(1, max(0.75, visualScale))
        let isHighlighted = isEnabled && (isSelected || configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: CarveRadius.control * scale, style: .continuous)
        let label = configuration.label
            .foregroundStyle(iconColor(isHighlighted: isHighlighted))
            .scaleEffect(scale)
            .frame(
                width: CarveSize.minimumHitTarget * scale,
                height: CarveSize.minimumHitTarget * scale
            )

        let surface = Group {
            if isEnabled, isSelected, background == .plain {
                // 표면 안 도구의 선택(시안 M2 · J1). 라이트의 밝은 바탕은 팔레트 표면과 거의 같아 무엇을 골랐는지 보이지 않았다
                // (2026-09-15 피드백). 라이트는 강조색 바탕에 밝은 아이콘으로 칠하고, 다크는 선택 배경이 표면과 이미 뚜렷해 그대로 둔다.
                label.background(colorScheme == .dark ? CarveColor.selected : CarveColor.accent, in: shape)
            } else if isHighlighted, background == .plain {
                // 눌림은 선택보다 옅게 — 실행 취소 · 다시 실행을 누를 때 선택처럼 보이지 않게 한다.
                label.background(colorScheme == .dark ? CarveColor.selected : CarveColor.fill, in: shape)
            } else if isHighlighted {
                label
                .background(CarveColor.selected, in: shape)
                .overlay {
                    shape.strokeBorder(CarveColor.accent.opacity(0.45), lineWidth: 1)
                }
            } else if background == .floating {
                label.carveSurface(.floatingControl, in: shape)
            } else {
                label
            }
        }

        surface
            .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
            .contentShape(Rectangle())
    }

    private func iconColor(isHighlighted: Bool) -> Color {
        if !isEnabled { return CarveColor.ink.opacity(0.25) }
        if background == .plain {
            // 라이트의 선택 바탕은 강조색이라 아이콘을 밝게 뒤집는다(대비 약 6.2:1).
            return isSelected && colorScheme != .dark ? CarveColor.canvas : CarveColor.ink
        }
        return isHighlighted ? CarveColor.accent : CarveColor.ink
    }
}
