//
//  CarveIcon.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import Resources

/// 선 아이콘. 24pt 그림 · 1.7pt 선이고 템플릿 이미지라 색은 `foregroundStyle` 로 준다(문서 6장 아이콘).
///
/// Feature 는 에셋 이름이나 번들 위치를 몰라도 된다. 경로는 `docs/design/assets/figma/*.svg` 프레임에서 옮겼다.
/// ``textFormat`` 만 선이 아니라 「가가」 글자를 윤곽선으로 고정한 것이다 — 글꼴에 따라 모양이 바뀌지 않게.
/// ``starFill`` 은 ``star`` 와 같은 경로를 채운 것이다(시안 N2 · N4).
public enum CarveIcon: CaseIterable, Sendable {
    // 헤더
    /// 서재 — 성경 목록을 여는 사이드바 토글.
    case library
    /// 이전 장.
    case previous
    /// 다음 장.
    case next
    /// 본문 설정(「가가」).
    case textFormat

    // 도구 팔레트
    case pen
    case eraser
    case lasso
    case undo
    case redo

    // 사이드바 하단
    case chart
    case settings

    // 상태 · 메뉴 · 탐색
    case checkmark
    case warning
    case chevronLeft
    case chevronRight
    /// 이전 필사 기록.
    case history
    /// 이미지 저장(절 롱탭 메뉴).
    case photo
    /// 위젯에 표시(절 롱탭 메뉴).
    case widget
    /// 지우기 · 삭제.
    case trash
    /// 더보기(···) — 즐겨찾기 카드의 메뉴 버튼(시안 N6).
    case more
    case help

    // 즐겨찾기(시안 N)
    /// 빈 별 — 사이드바 즐겨찾기 버튼 · 절 메뉴 「즐겨찾기에 추가」 · 빈 목록.
    case star
    /// 채운 별 — 절 번호 아래 즐겨찾기 표시 · 절 메뉴 「즐겨찾기 해제」 · 목록 제목과 해제 버튼.
    case starFill

    /// 템플릿으로 그리는 아이콘. 크기는 원본 24pt 다.
    public var image: Image {
        Image(asset: asset).renderingMode(.template)
    }

    var asset: ResourcesImages {
        switch self {
        case .library: ResourcesAsset.LineIcon.library
        case .previous: ResourcesAsset.LineIcon.previous
        case .next: ResourcesAsset.LineIcon.next
        case .textFormat: ResourcesAsset.LineIcon.textFormat
        case .pen: ResourcesAsset.LineIcon.pen
        case .eraser: ResourcesAsset.LineIcon.eraser
        case .lasso: ResourcesAsset.LineIcon.lasso
        case .undo: ResourcesAsset.LineIcon.undo
        case .redo: ResourcesAsset.LineIcon.redo
        case .chart: ResourcesAsset.LineIcon.chart
        case .settings: ResourcesAsset.LineIcon.settings
        case .checkmark: ResourcesAsset.LineIcon.checkmark
        case .warning: ResourcesAsset.LineIcon.warning
        case .chevronLeft: ResourcesAsset.LineIcon.chevronLeft
        case .chevronRight: ResourcesAsset.LineIcon.chevronRight
        case .history: ResourcesAsset.LineIcon.history
        case .photo: ResourcesAsset.LineIcon.photo
        case .widget: ResourcesAsset.LineIcon.widget
        case .trash: ResourcesAsset.LineIcon.trash
        case .more: ResourcesAsset.LineIcon.more
        case .help: ResourcesAsset.LineIcon.help
        case .star: ResourcesAsset.LineIcon.star
        case .starFill: ResourcesAsset.LineIcon.starFill
        }
    }
}
