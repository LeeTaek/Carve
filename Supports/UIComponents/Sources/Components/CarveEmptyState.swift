//
//  CarveEmptyState.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 빈 상태 — 제목 · 설명 · 선택적 액션(시안 E3 기록 없음, H2 차트 없음).
///
/// 화면을 빈 문장으로 채우지 않고 돌아갈 길을 준다(예: 「필사하러 가기」).
public struct CarveEmptyState: View {
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: 무엇이 비어 있는지.
    ///   - message: 언제 채워지는지 같은 설명.
    ///   - actionTitle: 액션 버튼 제목. `action` 과 함께 줄 때만 버튼이 생긴다.
    ///   - action: 액션 콜백.
    public init(
        _ title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: CarveSpacing.medium) {
            VStack(spacing: CarveSpacing.xSmall) {
                Text(title)
                    .font(CarveTypography.title)
                    .foregroundStyle(CarveColor.ink)
                if let message {
                    Text(message)
                        .font(CarveTypography.label)
                        .foregroundStyle(CarveColor.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.carve(.primary))
            }
        }
        .padding(CarveSpacing.large)
        .frame(maxWidth: .infinity)
    }
}
