//
//  CarveStatusMessage.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ClientInterfaces

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
    /// 다시 시도 버튼 제목. nil 이면 기본 제목이다 — 본문이 키 기반 `Text` 로 적어 환경 locale(앱 안 언어 고르기)을 바로 따른다.
    let retryTitle: String?
    private let onRetry: (() -> Void)?

    /// 다시 시도 버튼의 기본 제목 — ko 「다시 시도」 · en 「Try Again」.
    ///
    /// 정적 프로퍼티라 환경을 읽지 못하므로 지금 화면 언어(`AppLanguage.displayLocale()` — 앱 루트가 환경 locale 을 만드는 규칙과 같다)로 적는다.
    /// 화면에는 이 문자열을 붙잡지 않고 환경 locale 로 다시 적는다 — init 이 기본 제목을 알아보고 nil 로 둔다(즉시 전환 단계 3).
    nonisolated public static var defaultRetryTitle: String {
        UIComponentsCatalog.string("다시 시도", locale: AppLanguage.displayLocale())
    }

    /// - Parameters:
    ///   - kind: 결과 종류.
    ///   - message: 결과 문장(예: 「사진에 저장했어요」). 부르는 쪽이 앱 언어로 옮겨 준다.
    ///   - retryTitle: 다시 시도 버튼 제목. 기본은 `defaultRetryTitle` — 기본 제목은 화면 언어가 바뀌면 함께 바뀐다.
    ///   - onRetry: 다시 시도 콜백. 있을 때만 버튼이 생긴다.
    public init(
        _ kind: Kind,
        message: String,
        retryTitle: String = CarveStatusMessage.defaultRetryTitle,
        onRetry: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        // 기본 제목이면 문자열로 붙잡지 않는다 — 만든 뒤 앱 안에서 언어를 바꿔도 본문이 환경 locale 로 다시 적는다.
        // 부르는 쪽이 준 제목(「실행 취소」 등)은 그 쪽이 환경 locale 로 만들어 넘긴다.
        self.retryTitle = retryTitle == Self.defaultRetryTitle ? nil : retryTitle
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
                    retryLabel
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

    /// 다시 시도 버튼 글자. 부르는 쪽이 준 제목은 그대로 적고, 기본 제목은 키 기반 `Text` 라 환경 locale 을 따른다.
    private var retryLabel: Text {
        if let retryTitle {
            Text(verbatim: retryTitle)
        } else {
            Text("다시 시도", bundle: .module, comment: "결과 알림 줄의 다시 시도 버튼 기본 제목")
        }
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
