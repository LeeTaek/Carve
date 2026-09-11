//
//  CarveMetrics.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

/// 여백 규격(pt). 시안의 4pt 격자를 따른다.
public enum CarveSpacing {
    public static let xxSmall: CGFloat = 4
    public static let xSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    /// 팝오버 · 패널 안쪽 가로 여백(D1).
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
}

/// 모서리 규격(pt).
public enum CarveRadius {
    /// 컨트롤 안쪽 — 세그먼트 선택 표시(rx 9).
    public static let inner: CGFloat = 9
    /// 44pt 버튼 · 세그먼트 트랙 · 표면 안 버튼(rx 12).
    public static let control: CGFloat = 12
    /// 도구 팔레트 · 카드 · 확인 대화상자(rx 20).
    public static let card: CGFloat = 20
    /// 팝오버 · 시트(rx 24).
    public static let panel: CGFloat = 24
}

/// 아이콘 · 터치 영역 규격(문서 3-2 · 6장).
public enum CarveSize {
    /// 아이콘 그림 크기.
    public static let iconGlyph: CGFloat = 24
    /// 아이콘 선 굵기. 선은 에셋에 들어 있고, 코드로 그리는 선을 아이콘과 맞출 때 쓴다.
    public static let iconStroke: CGFloat = 1.7
    /// 최소 터치 영역이자 아이콘 버튼 한 변.
    public static let minimumHitTarget: CGFloat = 44
    /// 접힌 도구 팔레트의 원형 버튼(문서 4-1).
    public static let floatingToolButton: CGFloat = 64
}
