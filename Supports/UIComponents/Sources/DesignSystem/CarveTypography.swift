//
//  CarveTypography.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIKit

/// UI 글자 규격. 크기 · 굵기 · Dynamic Type 대응을 함께 정한다.
///
/// 시스템 텍스트 스타일 위에 만들어 사용자의 글자 크기 설정을 따른다. 시안의 "UI 주로 14pt" 를 한 값으로 고정하지 않는다.
///
/// | 역할 | 스타일 | 기본 크기 | 시안에서 |
/// |---|---|---|---|
/// | ``title`` | headline | 17pt semibold | 패널 · 시트 제목 — D1 「본문 설정」 |
/// | ``sectionTitle`` | footnote | 13pt medium | 설정 묶음 제목 — D1 「글꼴」 · 「화면과 필기」 |
/// | ``body`` | subheadline | 15pt | 행 제목 · 버튼 · 알림 문장 |
/// | ``label`` | footnote | 13pt | 컨트롤 라벨 · 값 · 세그먼트 항목 |
/// | ``caption`` | caption | 12pt | 행 설명 · 힌트 |
///
/// 시안의 11 · 12pt 설명은 한 단계씩 올렸다 — 설명 · 힌트 글자 크기는 문서 8-3 의 열린 결정이다.
public enum CarveTypography {
    /// 패널 · 시트 제목.
    public static let title: Font = .headline
    /// 설정 묶음 제목.
    public static let sectionTitle: Font = .footnote.weight(.medium)
    /// 행 제목 · 버튼 · 알림 문장.
    public static let body: Font = .subheadline
    /// 컨트롤 라벨 · 값 · 세그먼트 항목.
    public static let label: Font = .footnote
    /// 행 설명 · 힌트.
    public static let caption: Font = .caption

    /// 성경 본문 글꼴을 SwiftUI `Font` 로 옮긴다. 받은 글꼴 · 크기를 그대로 쓰고 **Dynamic Type 으로 키우지 않는다.**
    ///
    /// 본문 크기는 본문 설정이 정하고 필기 레이아웃 측정과 묶여 있어 UI 글자 확대 정책을 따르지 않는다.
    /// - Parameter font: 본문 설정이 고른 글꼴. 예: `FontCase.font(size:)`.
    public static func scripture(_ font: UIFont) -> Font {
        Font(font)
    }
}
