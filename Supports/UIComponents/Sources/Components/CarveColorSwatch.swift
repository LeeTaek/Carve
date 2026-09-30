//
//  CarveColorSwatch.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 펜 색 동그라미와 선택 테두리(시안 C · M 팔레트, J 다크 팔레트).
///
/// 색은 사용자가 고른 필기 색이라 외관에 따라 바꾸지 않는다. 대신 어두운 표면에서는 모든 동그라미에
/// 흰 40% 테두리를 둘러 검정 펜이 묻히지 않게 한다(테두리가 없으면 1.16:1).
/// 탭 · 길게 누르기와 VoiceOver 이름 · 선택 특성은 감싸는 쪽이 준다.
public struct CarveColorSwatch: View {
    private let color: Color
    private let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - color: 그릴 펜 색.
    ///   - isSelected: 선택 테두리를 그릴지.
    public init(_ color: Color, isSelected: Bool) {
        self.color = color
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .stroke(CarveColor.ink.opacity(colorScheme == .dark ? 0.6 : 0.35), lineWidth: 2)
                    .frame(width: 30, height: 30)
            }
            Circle()
                .fill(color)
                .overlay {
                    if colorScheme == .dark {
                        Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
        }
        .frame(width: 32, height: 32)
    }
}
