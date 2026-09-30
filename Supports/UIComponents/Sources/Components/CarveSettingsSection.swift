//
//  CarveSettingsSection.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 설정 묶음 — 묶음 제목과 그 아래 행들(시안 D 「글꼴」 · 「화면과 필기」, F 「필사」 · 「저장」 · 「지원」).
///
/// 묶음 사이 구분선은 담는 쪽이 ``CarveDivider`` 로 둔다.
public struct CarveSettingsSection<Content: View>: View {
    private let title: String?
    private let content: Content

    /// - Parameters:
    ///   - title: 묶음 제목. 없으면 행만 둔다.
    ///   - content: 행들.
    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            if let title {
                Text(title)
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
