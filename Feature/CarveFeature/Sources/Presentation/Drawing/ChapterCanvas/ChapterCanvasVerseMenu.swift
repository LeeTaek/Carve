//
//  ChapterCanvasVerseMenu.swift
//  FeatureCarve
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

/// 절 롱탭 메뉴가 떠 있는 상태(시안 E1).
///
/// 좌표는 둘이다. `contentPoint` 는 캔버스 content 좌표로 항목을 고른 뒤 기존 `historyRequested` · `eraseRequested`
/// 로 그대로 넘긴다. `anchor` · `verseFrame` 은 **창(window) 좌표**라 오버레이가 스크롤 위치와 무관하게 그린다 —
/// 스크롤 위치를 아는 것은 컨트롤러뿐이라 변환도 컨트롤러가 한다.
struct ChapterCanvasVerseMenu: Equatable {
    /// 롱탭한 절.
    let verse: Int
    /// 롱탭 지점(캔버스 content 좌표).
    let contentPoint: CGPoint
    /// 롱탭 지점(창 좌표). 메뉴를 그 가까이에 놓는다.
    let anchor: CGPoint
    /// 롱탭한 절 행 전체(원문 + 필기, 창 좌표). 가림막에서 이 자리만 비워 "들어 올린" 모양을 만든다.
    let verseFrame: CGRect
    /// 띄울 수 있는 항목(UI-2). 비어 있으면 메뉴를 만들지 않는다.
    let availability: ChapterCanvasMenuAvailability
}

extension ChapterCanvasFeature {
    /// content 좌표가 가리키는 절의 **행 전체** 사각형(content 좌표). 원문 반쪽과 필기 반쪽을 모두 덮는다.
    ///
    /// 컬럼은 반쪽이 둘이라 행 폭은 필사 폭의 두 배다(`ChapterLayoutHosting` — 원문 반쪽 | 필기 반쪽).
    static func verseRowRect(at point: CGPoint, state: State) -> CGRect? {
        guard let verse = verse(at: point, state: state),
              let layout = state.renderedLayout,
              let region = layout.region(verse: verse) else { return nil }
        let origin = state.renderedColumnOrigin
        return CGRect(
            x: 0,
            y: origin.y + region.writingRect.minY,
            width: layout.writingWidth * 2,
            height: region.writingRect.height
        )
    }
}
