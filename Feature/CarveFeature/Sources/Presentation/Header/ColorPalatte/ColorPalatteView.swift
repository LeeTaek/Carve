//
//  ColorPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

/// 시안 P1 「필기 색상」. 기본 색상 12개 · 고른 색 미리보기 · 시스템 색상 선택기 · 「완료」.
///
/// 고르는 즉시 펜에 반영되므로(리듀서 주석) 「완료」는 확정이 아니라 **닫기**다. 바깥을 눌러 닫아도 결과는 같다.
@ViewAction(for: ColorPalatteFeature.self)
public struct ColorPalatteView: View {
    @Bindable public var store: StoreOf<ColorPalatteFeature>

    /// 시안의 6 × 2 배치. 타일은 44pt 터치 영역을 갖는다(디자인 문서 5장).
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: CarveSpacing.xxSmall),
        count: 6
    )

    public init(store: StoreOf<ColorPalatteFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader("필기 색상") {
                Button("완료") { send(.done) }
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.accent)
                    .buttonStyle(.plain)
                    .frame(minWidth: CarveSize.minimumHitTarget, minHeight: CarveSize.minimumHitTarget)
            }

            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                sectionTitle("기본 색상")
                colorGrid

                sectionTitle("선택한 색상")
                InkPreview(
                    color: Color(uiColor: store.selectedColor.color),
                    lineWidth: store.pencilConfig.lineWidth
                )

                customColorRow
            }
            .padding(CarveSpacing.medium)
        }
        .frame(width: 320)
        .carvePresentationSurface()
        .presentationCompactAdaptation(.popover)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(CarveTypography.sectionTitle)
            .foregroundStyle(CarveColor.secondary)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: CarveSpacing.xxSmall) {
            ForEach(Array(ColorPalatteFeature.defaultColors.enumerated()), id: \.offset) { _, color in
                let isSelected = color.isSameColor(as: store.selectedColor.color)
                Button {
                    send(.setColor(color))
                } label: {
                    CarveColorSwatch(Color(uiColor: color), isSelected: isSelected)
                        .overlay {
                            if isSelected {
                                CarveIcon.checkmark.image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(Color(uiColor: color.contrastingMarkColor))
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: CarveSize.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.colorName(color))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// 시스템 색상 선택기로 넘어가는 줄 (디자인 문서 5장 — 「사용자 색상은 시스템 색상 선택기로 연결한다」).
    ///
    /// 불투명도는 열어 두지 않는다. 팔레트에는 투명도를 보여 줄 자리가 없고, 반투명 잉크는
    /// 필사 화면에서 밑줄과 섞여 사용자가 왜 흐린지 알기 어렵다.
    private var customColorRow: some View {
        ColorPicker(selection: customColorBinding, supportsOpacity: false) {
            Text("다른 색상 고르기")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
        }
        .padding(.horizontal, CarveSpacing.small)
        .frame(minHeight: CarveSize.minimumHitTarget)
        .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control))
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: store.selectedColor.color) },
            set: { send(.setColor(UIColor($0))) }
        )
    }

    /// VoiceOver 가 읽을 색 이름. 시안 P1 의 12색 순서와 같다.
    static func colorName(_ color: UIColor) -> String {
        let names = [
            "먹색", "초록", "갈색", "붉은색", "파랑", "보라",
            "노랑", "흰색", "회색", "짙은 초록", "분홍", "베이지"
        ]
        guard let index = ColorPalatteFeature.defaultColors.firstIndex(where: { $0.isSameColor(as: color) }),
              index < names.count else {
            return "색상"
        }
        return names[index]
    }
}

extension UIColor {
    /// 같은 색인가 — 저장·복원을 거치며 생기는 부동소수 오차를 감안해 채널당 1/255 까지 같게 본다.
    func isSameColor(as other: UIColor) -> Bool {
        var lhs = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0), alpha: CGFloat(0))
        var rhs = lhs
        guard getRed(&lhs.red, green: &lhs.green, blue: &lhs.blue, alpha: &lhs.alpha),
              other.getRed(&rhs.red, green: &rhs.green, blue: &rhs.blue, alpha: &rhs.alpha) else {
            return self == other
        }
        let tolerance: CGFloat = 1.0 / 255
        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
    }
}
