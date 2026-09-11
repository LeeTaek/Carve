//
//  ChapterCanvasVerseMenu.swift
//  FeatureCarve
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

import ComposableArchitecture

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

extension ChapterCanvasFeature {
    /// 절 메뉴 액션(시안 E1). 항목은 기존 `historyRequested` · `eraseRequested` 흐름으로 넘긴다.
    func reduceVerseMenu(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .verseMenuRequested(point, anchor, verseFrame):
            // 할 수 없는 일만 남은 절이면 메뉴를 올리지 않는다 (UI-2).
            let availability = Self.menuAvailability(at: point, state: state)
            guard !availability.isEmpty, let verse = Self.verse(at: point, state: state) else { return .none }
            state.verseMenu = ChapterCanvasVerseMenu(
                verse: verse,
                contentPoint: point,
                anchor: anchor,
                verseFrame: verseFrame,
                availability: availability
            )
            return .none

        case .verseMenuDismissed:
            state.verseMenu = nil
            return .none

        case .verseMenuHistoryTapped:
            guard let menu = state.verseMenu, menu.availability.canViewHistory else { return .none }
            state.verseMenu = nil
            state.historyAnchorFrame = menu.verseFrame
            return .send(.historyRequested(at: menu.contentPoint))

        case .verseMenuEraseTapped:
            guard let menu = state.verseMenu, menu.availability.canErase else { return .none }
            state.verseMenu = nil
            return .send(.eraseRequested(at: menu.contentPoint))

        default:
            return .none
        }
    }
}
