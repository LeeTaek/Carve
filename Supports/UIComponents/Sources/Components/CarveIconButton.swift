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
    private let action: () -> Void

    /// - Parameters:
    ///   - icon: 그릴 아이콘.
    ///   - accessibilityLabel: VoiceOver 이름. 아이콘만 두는 버튼이라 반드시 준다(예: 「본문 설정」).
    ///   - isSelected: 선택 · 열림 상태(예: 팝오버가 열린 본문 설정 버튼).
    ///   - background: 버튼 바탕.
    ///   - action: 탭 콜백.
    public init(
        _ icon: CarveIcon,
        accessibilityLabel: String,
        isSelected: Bool = false,
        background: Background = .floating,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
        self.background = background
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon.image
        }
        .buttonStyle(CarveIconButtonStyle(isSelected: isSelected, background: background))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CarveIconButtonStyle: ButtonStyle {
    let isSelected: Bool
    let background: CarveIconButton.Background

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isHighlighted = isEnabled && (isSelected || configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
        let label = configuration.label
            .foregroundStyle(iconColor(isHighlighted: isHighlighted))
            .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
            .contentShape(shape)

        if isHighlighted {
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

    private func iconColor(isHighlighted: Bool) -> Color {
        if !isEnabled { return CarveColor.ink.opacity(0.25) }
        return isHighlighted ? CarveColor.accent : CarveColor.ink
    }
}
