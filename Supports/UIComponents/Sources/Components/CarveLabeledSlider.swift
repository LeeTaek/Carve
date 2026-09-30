//
//  CarveLabeledSlider.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 제목 · 현재 값 · 슬라이더(시안 D 글자 크기 · 줄 간격 · 자간, 도구 굵기).
///
/// VoiceOver 는 슬라이더 하나로 제목과 값을 함께 읽는다 — 보이는 제목 줄은 중복이라 숨긴다.
public struct CarveLabeledSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    private let title: String
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride?
    private let valueText: String

    /// - Parameters:
    ///   - title: 제목.
    ///   - value: 값.
    ///   - range: 범위.
    ///   - step: 눈금. `nil` 이면 연속 값이다.
    ///   - valueText: 오른쪽에 적는 현재 값(예: `20 pt`). VoiceOver 값으로도 쓴다.
    public init(
        _ title: String,
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value.Stride? = nil,
        valueText: String
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: CarveSpacing.xSmall) {
                Text(title)
                    .foregroundStyle(CarveColor.ink)
                Spacer(minLength: 0)
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(CarveColor.accent)
            }
            .font(CarveTypography.label)
            .accessibilityHidden(true)

            CarveSlider(title, value: $value, in: range, step: step)
                .accessibilityValue(valueText)
        }
    }
}
