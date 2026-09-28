//
//  ArrivalNoticeView.swift
//  CarveFeature
//
//  늦게 도착한 필사의 안내 — 「다른 필사가 도착했어요 · 확인하기」 (2026-09-21 후속 리뷰 P0-3, 사용자 결정).
//

import SwiftUI

import UIComponents

/// 도착 안내. **사라지는 안내로 두지 않는다** — 확인하기 · 다시 시도가 끝날 때까지 남는다. 「남은 필기」 안내만 닫을 수 있다.
///
/// 편집한 장은 도착한 필사로 자동으로 바꾸지 않으므로, 사용자가 이 안내로 알고 고른다. 모양은 다른 결과 안내(`CarveStatusMessage`)와 같다.
struct ArrivalNoticeView: View {
    let notice: ArrivalNotice
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: CarveSpacing.small) {
            leading
                .accessibilityHidden(true)
            Text(notice.message)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let title = notice.actionTitle {
                Button(action: onAction) {
                    Text(title)
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
            if case .draftsHidden = notice {
                Button("닫기", action: onDismiss)
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.secondary)
                    .frame(minHeight: CarveSize.minimumHitTarget)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, CarveSpacing.large)
        .padding(.trailing, notice.actionTitle == nil ? CarveSpacing.large : CarveSpacing.small)
        .padding(.vertical, CarveSpacing.xSmall)
        .frame(minHeight: 60)
        .carveSurface(.solid, in: Capsule())
        .accessibilityElement(children: .contain)
        .onChange(of: notice, initial: true) { _, notice in
            AccessibilityNotification.Announcement(notice.message).post()
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch notice {
        case .confirming:
            ProgressView()
        case .reloadFailed:
            CarveIcon.warning.image
                .foregroundStyle(CarveColor.danger)
        case .arrived, .draftsHidden:
            CarveIcon.history.image
                .foregroundStyle(CarveColor.accent)
        }
    }
}
