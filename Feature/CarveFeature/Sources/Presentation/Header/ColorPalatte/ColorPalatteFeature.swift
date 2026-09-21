//
//  ColorPalatteFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture

/// 팔레트 색 칸 하나를 바꾸는 팝오버 (시안 P1 「필기 색상」).
///
/// **고르는 즉시 도구에 반영한다** (디자인 문서 5장 — 팔레트 세부 옵션). 그래서 이 리듀서는
/// 세 가지를 함께 쓴다: 편집 중인 칸의 색(`palatteColors[index]`), 선택 칸(`selectedColorIndex`),
/// 그리고 펜 설정(`pencilConfig.lineColor`). 셋을 한 자리에서 쓰지 않으면 「완료」를 눌러야만
/// 펜에 반영되던 이전 동작으로 되돌아간다.
@Reducer
public struct ColorPalatteFeature {
    @ObservableState
    public struct State {
        @Shared(.appStorage("palatteColorSet")) public var palatteColors: [CodableColor] = []
        @Shared(.appStorage("selectedColorIndex")) public var selectedColorIndex: Int = 0
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        /// 편집 중인 팔레트 칸.
        public var index: Int
        public var selectedColor: CodableColor

        public init(index: Int, color: CodableColor) {
            self.index = index
            self.selectedColor = color
        }
    }

    /// 시안 P1 의 기본 색상 12개 (6 × 2). 값은 `p1-palette-colors.svg` 에서 그대로 옮겼다.
    ///
    /// 흰색은 종이와 구분되지 않으므로 그리는 쪽(`CarveColorSwatch`)이 테두리를 둘러 준다.
    public static let defaultColors: [UIColor] = [
        UIColor(hex: 0x303B36), UIColor(hex: 0x476550), UIColor(hex: 0x99785F),
        UIColor(hex: 0xA4453C), UIColor(hex: 0x476D91), UIColor(hex: 0x77618F),
        UIColor(hex: 0xC6973C), UIColor(hex: 0xFFFFFF), UIColor(hex: 0x8B9290),
        UIColor(hex: 0x244A3A), UIColor(hex: 0xCA8F83), UIColor(hex: 0xC3B5A4)
    ]

    public enum Action: ViewAction {
        case view(View)

        public enum View {
            case setColor(UIColor)
            case done
        }
    }

    @Dependency(\.dismiss) private var dismiss

    public init() { }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.setColor(let color)):
                let picked = CodableColor(color: color)
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.selectedColor = picked
                    state.$palatteColors.withLock { colors in
                        guard state.index < colors.count else { return }
                        colors[state.index] = picked
                    }
                    // 고른 칸을 그대로 쓰게 한다 — 팝오버를 닫고 다시 고르게 하지 않는다.
                    state.$selectedColorIndex.withLock { $0 = state.index }
                    state.$pencilConfig.withLock { $0.lineColor = picked }
                }
            case .view(.done):
                return .run { _ in await dismiss() }
            }
            return .none
        }
    }
}

extension UIColor {
    /// 시안 SVG 의 `#RRGGBB` 를 그대로 옮기기 위한 생성자.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// 이 색 위에 얹을 표시(체크)의 색. 밝은 색 위에서는 잉크색, 어두운 색 위에서는 흰색이다.
    ///
    /// 흰색 타일에 흰 체크를 그리면 선택이 보이지 않는다. 상대 휘도(WCAG)로 갈라 접근성 대비를 지킨다.
    var contrastingMarkColor: UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.5 ? UIColor(hex: 0x303B36) : .white
    }
}
