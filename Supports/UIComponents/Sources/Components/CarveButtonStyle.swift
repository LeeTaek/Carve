//
//  CarveButtonStyle.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 버튼 역할. 시안의 버튼은 모두 톤 바탕이고 역할은 **글자색**으로 나눈다.
public enum CarveButtonRole: Sendable {
    /// 주 동작 — 강조색 글자. 「본문 모양 초기화」 · 「완료」 · 「필사하러 가기」.
    case primary
    /// 보조 동작 — 잉크 글자. 「나중에」 · 「취소」.
    case secondary
    /// 되돌릴 수 없는 동작 — 위험색 글자. 「모든 필사 데이터 삭제」.
    case destructive
}

/// Carve 글자 버튼. 최소 44pt 높이 · 12pt 모서리 · 톤 바탕.
///
/// 바탕은 놓인 자리를 따른다 — 표면(``SwiftUI/View/carveSurface(_:in:)`` · 팝오버) 안이면 `fill`,
/// 화면 바탕 위면 `surface`. 비활성은 `.disabled(_:)` 로 준다.
public struct CarveButtonStyle: ButtonStyle {
    private let role: CarveButtonRole
    private let fillsWidth: Bool

    @Environment(\.carveBackdrop) private var backdrop
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - role: 버튼 역할.
    ///   - fillsWidth: 가로를 가득 채울지. 패널 아래쪽 버튼(D1 「본문 모양 초기화」)에 쓴다.
    public init(_ role: CarveButtonRole = .primary, fillsWidth: Bool = false) {
        self.role = role
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
        configuration.label
            .font(CarveTypography.body)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, CarveSpacing.medium)
            .padding(.vertical, CarveSpacing.xSmall)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: CarveSize.minimumHitTarget)
            .background(backdrop.controlFill, in: shape)
            .contentShape(shape)
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private var foreground: Color {
        switch role {
        case .primary: CarveColor.accent
        case .secondary: CarveColor.ink
        case .destructive: CarveColor.danger
        }
    }

    private func opacity(isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return isPressed ? 0.6 : 1
    }
}

public extension ButtonStyle where Self == CarveButtonStyle {
    /// Carve 글자 버튼. ``CarveButtonStyle`` 참고.
    static func carve(_ role: CarveButtonRole = .primary, fillsWidth: Bool = false) -> CarveButtonStyle {
        CarveButtonStyle(role, fillsWidth: fillsWidth)
    }
}
