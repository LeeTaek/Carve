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
///
/// 띄울 때는 `settingsPopup(_:)` 을 쓴다. 가림막은 제자리에서 흐려지고 카드는 가운데서 커지며 나타난다.
@ViewAction(for: PopupFeature.self)
public struct PopupView: View {
    @Bindable public var store: StoreOf<PopupFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 가림막 · 카드가 보이는가. cover 는 전환 없이 뜨고 빠지므로 나타남 · 사라짐은 이 값으로 그린다.
    @State private var isShown = false
    /// 닫기를 시작했는가. 걷힌 뒤 다시 나타나지 않게 하고, 걷히는 동안 버튼을 한 번만 받는다.
    @State private var isClosing = false

    public init(store: StoreOf<PopupFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            // 가림막은 뒤 화면이 잠시 멈췄다는 표시라 움직이지 않는다 — 제자리에서 흐려지고 걷힌다.
            CarveColor.scrim
                .ignoresSafeArea()
                .opacity(isShown ? 1 : 0)
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
            // 카드는 가운데서 살짝 커지며 나타난다 — 절 메뉴(`VerseMenuOverlay`)와 같은 값이다.
            .scaleEffect(isShown || reduceMotion ? 1 : 0.96)
            .opacity(isShown ? 1 : 0)
            .padding(CarveSpacing.large)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            guard !isClosing else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
                isShown = true
            }
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
                    close(with: .cancel)
                }
            }

            actionButton(
                store.confirmTitle,
                background: store.role == .destructive ? CarveColor.danger : CarveColor.selected,
                foreground: store.role == .destructive ? CarveColor.canvas : CarveColor.accent,
                weight: store.role == .destructive ? .semibold : .regular
            ) {
                // 전체 삭제는 대화상자를 둔 채 결과 문구로 바뀐다 — 걷지 않고 바로 보낸다.
                if store.confirmAction == .dismiss {
                    close(with: .confirm)
                } else {
                    send(.confirm)
                }
            }
        }
    }

    /// 대화상자를 닫는 버튼 — 가림막 · 카드를 먼저 걷은 뒤 액션을 보낸다. 그다음 cover 는 전환 없이 빠진다.
    /// 취소와 `.dismiss` 확인은 부모가 반드시 닫아야 한다 — 닫지 않으면 걷힌 채 빈 cover 가 화면을 막는다.
    private func close(with action: PopupFeature.Action.View) {
        // 걷히는 동안 다시 누르면 액션이 두 번 간다.
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.16)) {
            isShown = false
        } completion: {
            // cover 를 빼는 상태 변경에 전환 끄기를 직접 싣는다. `settingsPopup` 의 `.transaction` 만으로는
            // iPadOS 27.2 실기기에서 cover 가 아래로 내려가며 빠졌다(2026-09-29).
            send(action, transaction: .withoutAnimation)
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

extension View {
    /// 설정 대화상자(시안 F2)를 창 전체에 띄운다.
    ///
    /// 설정 화면은 분할 보기의 한 열이라 그 안에서 덮으면 사이드바와 패널 밖이 가려지지 않는다 — 그래서 cover 로 띄운다.
    /// cover 는 띄운 화면을 통째로 아래에서 올리므로 가림막까지 카드와 함께 올라온다. 그 전환은 끄고,
    /// 나타남 · 사라짐은 `PopupView` 가 가림막과 카드를 따로 움직여 그린다.
    func settingsPopup(_ item: Binding<StoreOf<PopupFeature>?>) -> some View {
        background {
            Color.clear
                .fullScreenCover(item: item) { store in
                    PopupView(store: store)
                        .presentationBackground(.clear)
                }
                // 빈 배경에만 건다 — 화면 본문의 애니메이션은 건드리지 않는다.
                .transaction { $0.disablesAnimations = true }
        }
    }
}

private extension Transaction {
    /// cover 를 전환 없이 뺄 때 쓴다 — 사라짐은 `PopupView` 가 이미 그렸다.
    static var withoutAnimation: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}
