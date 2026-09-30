//
//  CarveStatusMessage.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 성공 · 실패를 짧게 알리는 줄(시안 G2 저장 결과).
///
/// 실패에는 사라지는 알림만 두지 않고 다시 시도를 함께 둔다(문서 7장 문구). 띄우는 시점 · 위치 · 사라지는 시간과
/// VoiceOver 알림(announcement)은 Feature 가 정한다.
public struct CarveStatusMessage: View {
    /// 결과 종류. 아이콘과 색만이 아니라 문장으로도 결과를 말해야 한다.
    public enum Kind: Sendable {
        case success
        case failure
    }

    private let kind: Kind
    private let message: String
    private let retryTitle: String
    private let onRetry: (() -> Void)?

    /// - Parameters:
    ///   - kind: 결과 종류.
    ///   - message: 결과 문장(예: 「사진에 저장했어요」).
    ///   - retryTitle: 다시 시도 버튼 제목.
    ///   - onRetry: 다시 시도 콜백. 있을 때만 버튼이 생긴다.
    public init(
        _ kind: Kind,
        message: String,
        retryTitle: String = "다시 시도",
        onRetry: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: CarveSpacing.small) {
            icon.image
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(message)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(CarveTypography.label)
                        .foregroundStyle(CarveColor.accent)
                        .padding(.horizontal, CarveSpacing.medium)
                        .frame(minHeight: 36)
                        .background(CarveColor.selected, in: Capsule())
                        .frame(minHeight: CarveSize.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CarveSpacing.large)
        .padding(.trailing, onRetry == nil ? CarveSpacing.large : CarveSpacing.small)
        .padding(.vertical, CarveSpacing.xSmall)
        .frame(minHeight: 60)
        .carveSurface(.solid, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var icon: CarveIcon {
        switch kind {
        case .success: .checkmark
        case .failure: .warning
        }
    }

    private var iconColor: Color {
        switch kind {
        case .success: CarveColor.accent
        case .failure: CarveColor.danger
        }
    }
}
