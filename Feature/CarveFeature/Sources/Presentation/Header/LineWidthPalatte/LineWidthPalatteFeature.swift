//
//  LineWidthPalatteFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import Foundation

import ComposableArchitecture

/// 펜 굵기 팝오버 (시안 P2 「펜 굵기」).
///
/// 시안의 「빠른 선택 세 칸」은 팔레트가 이미 갖고 있는 **굵기 칸 세 개**(`lineWidthSet`)다.
/// 시안의 0.3 · 0.5 · 0.8 mm 는 비교용 값이고 실제 값은 사용자가 조절한 것을 쓴다(디자인 문서 5장).
/// 칸을 고르면 그 칸이 선택되고, 슬라이더는 **선택한 칸의 값**을 바꾼다 — 고르는 즉시 펜에 반영한다.
@Reducer
public struct LineWidthPalatteFeature {
    @ObservableState
    public struct State {
        @Shared(.appStorage("lineWidthSet")) public var lineWidths: [CGFloat] = []
        @Shared(.appStorage("selectedWidthIndex")) public var selectedWidthIndex: Int = 0
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        /// 지금 조절하는 칸.
        public var index: Int
        public var lineWidth: CGFloat

        public init(lineWidth: CGFloat, index: Int) {
            self.lineWidth = lineWidth
            self.index = index
        }
    }

    /// 슬라이더 범위(pt)와 눈금. 표시는 mm 이고 `pt / 4` 로 환산한다 — 팔레트의 기존 표기와 같다.
    /// 눈금 0.4pt = 0.1mm 라 표시값이 흔들리지 않는다.
    public static let widthRange: ClosedRange<CGFloat> = 1...15
    public static let widthStep: CGFloat = 0.4

    public enum Action: ViewAction {
        case setWidth(CGFloat)
        case view(View)

        public enum View {
            case selectSlot(Int)
            case done
        }
    }

    @Dependency(\.dismiss) private var dismiss

    public init() { }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setWidth(let width):
                state.lineWidth = width
                state.$lineWidths.withLock { widths in
                    guard state.index < widths.count else { return }
                    widths[state.index] = width
                }
                state.$pencilConfig.withLock { $0.lineWidth = width }
            case .view(.selectSlot(let index)):
                guard index < state.lineWidths.count else { return .none }
                state.index = index
                state.lineWidth = state.lineWidths[index]
                state.$selectedWidthIndex.withLock { $0 = index }
                state.$pencilConfig.withLock { $0.lineWidth = state.lineWidths[index] }
            case .view(.done):
                return .run { _ in await dismiss() }
            }
            return .none
        }
    }
}
