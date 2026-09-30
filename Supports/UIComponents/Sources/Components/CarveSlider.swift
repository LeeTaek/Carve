//
//  CarveSlider.swift
//  UIComponents
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

/// Carve 슬라이더. 기존 `CustomSlider` 를 2.0 규격으로 옮긴 것이다.
///
/// 시스템 `Slider` 에 강조색만 입힌다 — VoiceOver 조절 동작 · 키보드 조작 · iOS 26 재질을 그대로 받는다.
/// 기존 구현은 드래그 제스처를 직접 그려 VoiceOver 로 값을 바꿀 수 없었다.
public struct CarveSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    private let title: String
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride?

    /// - Parameters:
    ///   - title: VoiceOver 이름. 화면에는 그리지 않는다 — 보이는 제목은 ``CarveLabeledSlider`` 가 둔다.
    ///   - value: 값.
    ///   - range: 범위.
    ///   - step: 눈금. `nil` 이면 연속 값이다(기존 `isFloat: true`).
    public init(_ title: String, value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step) { Text(title) }
            } else {
                Slider(value: $value, in: range) { Text(title) }
            }
        }
        .tint(CarveColor.accent)
    }
}
