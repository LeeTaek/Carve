//
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 시안 P2 「펜 굵기」. 빠른 선택 세 칸 · 굵기 조절 슬라이더 · 선 미리보기 · 「완료」.
///
/// 고르는 즉시 펜에 반영되므로 「완료」는 확정이 아니라 **닫기**다.
@ViewAction(for: LineWidthPalatteFeature.self)
public struct LineWidthPalatteView: View {
    @Bindable public var store: StoreOf<LineWidthPalatteFeature>

    public init(store: StoreOf<LineWidthPalatteFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader("펜 굵기") {
                Button("완료") { send(.done) }
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.accent)
                    .buttonStyle(.plain)
                    .frame(minWidth: CarveSize.minimumHitTarget, minHeight: CarveSize.minimumHitTarget)
            }

            VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                Text("굵기를 눌러 고르고, 아래에서 세밀하게 맞춰요.")
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.secondary)

                quickPicks

                CarveLabeledSlider(
                    "굵기 조절",
                    value: $store.lineWidth.sending(\.setWidth),
                    in: LineWidthPalatteFeature.widthRange,
                    step: LineWidthPalatteFeature.widthStep,
                    valueText: Self.millimeters(store.lineWidth)
                )

                InkPreview(
                    color: Color(uiColor: store.pencilConfig.lineColor.color),
                    lineWidth: store.lineWidth
                )
            }
            .padding(CarveSpacing.medium)
        }
        .frame(width: 320)
        .carvePresentationSurface()
        .presentationCompactAdaptation(.popover)
    }

    /// 굵기 칸 세 개. 각 칸은 그 칸의 실제 값으로 선을 그려 보여 준다.
    private var quickPicks: some View {
        HStack(spacing: CarveSpacing.xSmall) {
            ForEach(Array(store.lineWidths.enumerated()), id: \.offset) { index, width in
                let isSelected = index == store.index
                Button {
                    send(.selectSlot(index))
                } label: {
                    VStack(spacing: CarveSpacing.xSmall) {
                        Capsule()
                            .fill(CarveColor.ink)
                            .frame(height: max(1, width))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, CarveSpacing.small)
                        Text(Self.millimeters(width))
                            .font(CarveTypography.label)
                            .monospacedDigit()
                            .foregroundStyle(CarveColor.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: CarveSize.minimumHitTarget)
                    .padding(.vertical, CarveSpacing.small)
                    .background(
                        isSelected ? CarveColor.selected : CarveColor.fill,
                        in: RoundedRectangle(cornerRadius: CarveRadius.control)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("굵기 \(Self.millimeters(width))")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// 팔레트와 같은 표기 — PencilKit 의 pt 를 mm 로 환산해 적는다.
    static func millimeters(_ lineWidth: CGFloat) -> String {
        String(format: "%.1f mm", lineWidth / 4)
    }
}
