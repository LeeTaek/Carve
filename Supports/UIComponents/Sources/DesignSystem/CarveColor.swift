//
//  CarveColor.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import Resources

/// Carve 2.0 색 토큰. 값이 아니라 **역할**로 고른다.
///
/// 값은 `Shared/Resources` 색 에셋의 기본 · Dark 외관에 있고, 출처는 `docs/design/ui-design-direction.md` 3-1 이다.
/// 기존 화면이 쓰는 `Color.Brand`(CarveToolkit)는 1.x 값 그대로 두고, 화면을 옮길 때 이 토큰으로 바꾼다.
///
/// - Important: 필사 영역(종이 · 원문 · 필기 · 가이드)에는 쓰지 않는다. 다크에서도 밝게 유지하는 영역이라
///   ``CarveColor/Paper`` 를 쓴다(결정 8-1 안 1). 사용자가 고른 펜 색도 토큰이 아니다.
public enum CarveColor {
    /// 화면 바탕 · 헤더.
    public static let canvas = ResourcesAsset.Theme.canvas.swiftUIColor
    /// 팔레트 · 사이드바 · 팝오버 · 시트의 표면.
    public static let surface = ResourcesAsset.Theme.surface.swiftUIColor
    /// 선택한 도구 · 행의 배경.
    public static let selected = ResourcesAsset.Theme.selected.swiftUIColor
    /// 표면 안의 구분선.
    public static let divider = ResourcesAsset.Theme.divider.swiftUIColor
    /// 기본 글자 · 아이콘.
    public static let ink = ResourcesAsset.Theme.ink.swiftUIColor
    /// 설명 · 보조 라벨. 다크에서는 `selected` 위에 두지 않는다(4.34:1).
    public static let secondary = ResourcesAsset.Theme.textSecondary.swiftUIColor
    /// 강조 · 선택 · 링크 · 값.
    public static let accent = ResourcesAsset.Theme.accent.swiftUIColor
    /// 지우기 · 삭제. 다크에서는 `selected` 위에 두지 않는다(3.86:1).
    public static let danger = ResourcesAsset.Theme.danger.swiftUIColor
    /// 시트 · 대화상자 뒤 가림막.
    public static let scrim = ResourcesAsset.Theme.scrim.swiftUIColor
    /// 표면 안에 놓인 컨트롤의 바탕 — 세그먼트 트랙 · 표면 안 버튼(시안 D1 · J3).
    public static let fill = ResourcesAsset.Theme.fill.swiftUIColor

    /// 필사 영역 전용 색. 외관(라이트 · 다크)과 무관하게 같은 값이다.
    ///
    /// 종이는 배경 장식이다 — 이 색을 칠하는 뷰가 원문 · 필기 열의 x · 폭을 바꾸면 안 된다(단일 Canvas 설계 §9).
    public enum Paper {
        /// 종이.
        public static let background = ResourcesAsset.Paper.background.swiftUIColor
        /// 종이 위 성경 본문.
        public static let text = ResourcesAsset.Paper.text.swiftUIColor
        /// 필기 가이드 줄.
        public static let guide = ResourcesAsset.Paper.guide.swiftUIColor
        /// 종이 위 보조 글자 — 열 라벨(「말씀」 · 「나의 필사」). 다크에서도 종이 위라 라이트 값이다(시안 J1).
        public static let secondary = ResourcesAsset.Paper.textSecondary.swiftUIColor
        /// 종이 위 강조 — 절 번호.
        public static let accent = ResourcesAsset.Paper.accent.swiftUIColor
    }
}
