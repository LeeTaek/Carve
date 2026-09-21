//
//  PopupView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 설정의 확인 · 알림 대화상자 (시안 F2).
///
/// 화면 가운데에 카드로 뜨고 뒤는 가린다 — 되돌릴 수 없는 동작이라 바깥을 눌러 닫지 않는다.
/// 되돌릴 수 없는 동작(`.destructive`)에만 경고 표시와 빨간 확인 버튼을 둔다.
@ViewAction(for: PopupFeature.self)
public struct PopupView: View {
    @Bindable public var store: StoreOf<PopupFeature>

    public init(store: StoreOf<PopupFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            CarveColor.scrim
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: CarveSpacing.large) {
                if store.role == .destructive {
                    warningMark
                }

                VStack(spacing: CarveSpacing.small) {
                    if let title = store.title {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CarveColor.ink)
                            .accessibilityAddTraits(.isHeader)
                    }

                    VStack(spacing: CarveSpacing.xxSmall) {
                        Text(store.body)
                            .font(CarveTypography.body)
                            .foregroundStyle(CarveColor.ink)
                        if let emphasis = store.emphasis {
                            Text(emphasis)
                                .font(CarveTypography.body)
                                .foregroundStyle(CarveColor.danger)
                        }
                    }

                    if let hint = store.hint {
                        Text(hint)
                            .font(CarveTypography.label)
                            .foregroundStyle(CarveColor.secondary)
                            .padding(.top, CarveSpacing.xSmall)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: 420)
            .carveSurface(.solid, in: RoundedRectangle(cornerRadius: CarveRadius.panel))
            .padding(CarveSpacing.large)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    /// 시안 F2 의 빨간 동그라미 경고 표시.
    private var warningMark: some View {
        CarveIcon.warning.image
            .foregroundStyle(CarveColor.danger)
            .frame(width: CarveSize.iconGlyph, height: CarveSize.iconGlyph)
            .padding(CarveSpacing.small)
            .background(CarveColor.danger.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    /// 시안 F2 의 두 버튼. 대화상자 표면은 라이트에서 종이색이라 기본 컨트롤 바탕(`fill`)이 묻힌다 —
    /// 여기서는 두 버튼 다 바탕을 명시해 눌 수 있는 자리임을 분명히 한다.
    private var actions: some View {
        HStack(spacing: CarveSpacing.small) {
            if let cancelTitle = store.cancelTitle {
                actionButton(cancelTitle, background: CarveColor.selected, foreground: CarveColor.ink) {
                    send(.cancel)
                }
            }

            actionButton(
                store.confirmTitle,
                background: store.role == .destructive ? CarveColor.danger : CarveColor.selected,
                foreground: store.role == .destructive ? CarveColor.canvas : CarveColor.accent,
                weight: store.role == .destructive ? .semibold : .regular
            ) {
                send(.confirm)
            }
        }
    }

    private func actionButton(
        _ title: String,
        background: Color,
        foreground: Color,
        weight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CarveTypography.body)
                .fontWeight(weight)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: CarveSize.minimumHitTarget)
                .background(background, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
