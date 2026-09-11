//
//  CarveSegmentedPicker.swift
//  UIComponents
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

/// 여러 값 중 하나를 고르는 세그먼트(시안 D 글꼴 선택). 기존 `SegmentedPicker` 를 2.0 규격으로 옮긴 것이다.
///
/// 항목은 트랙 폭을 나눠 가진다. 선택은 글자색만이 아니라 바탕 모양으로도 보이고, 각 항목은 버튼이라
/// VoiceOver 가 선택된 항목을 알린다. 항목 한 칸의 높이는 44pt 다.
public struct CarveSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    @Binding private var selection: SelectionValue
    private let items: [SelectionValue]
    private let content: (SelectionValue) -> Content

    @Namespace private var namespace
    @Environment(\.carveBackdrop) private var backdrop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - selection: 선택 값.
    ///   - items: 고를 수 있는 값. 이 순서로 놓인다.
    ///   - content: 항목 라벨. 글꼴을 따로 주면 그 글꼴이 이긴다(예: 글꼴 이름을 그 글꼴로 보이기).
    public init(
        selection: Binding<SelectionValue>,
        items: [SelectionValue],
        @ViewBuilder content: @escaping (SelectionValue) -> Content
    ) {
        self._selection = selection
        self.items = items
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(.horizontal, CarveSpacing.xxSmall)
        .background(
            backdrop.controlFill,
            in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
        )
    }

    private func segment(_ item: SelectionValue) -> some View {
        let isSelected = item == selection
        return Button {
            guard !isSelected else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                selection = item
            }
        } label: {
            content(item)
                .font(CarveTypography.label)
                .foregroundStyle(isSelected ? CarveColor.ink : CarveColor.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CarveSpacing.xxSmall)
                .frame(maxWidth: .infinity, minHeight: CarveSize.minimumHitTarget)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: CarveRadius.inner, style: .continuous)
                            .fill(CarveColor.selected)
                            .padding(.vertical, CarveSpacing.xxSmall)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
