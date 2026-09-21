//
//  ChapterCanvasVerseMenu.swift
//  FeatureCarve
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

import ComposableArchitecture

/// 절 롱탭 메뉴가 떠 있는 상태(시안 E1 · N1).
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
    /// 절 메뉴 액션(시안 E1 · N1 · G1). 기록 · 지우기는 기존 `historyRequested` · `eraseRequested` 흐름으로 넘기고,
    /// 즐겨찾기 · 이미지 저장은 이 Feature 가 모르는 저장소 · 사진 보관함의 일이라 부모(`CarveDetailFeature`)에 맡긴다.
    func reduceVerseMenu(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .verseMenuRequested(point, anchor, verseFrame):
            // 절을 찾지 못한 자리면 메뉴를 올리지 않는다 (UI-2). 절을 찾았으면 적어도 즐겨찾기는 할 수 있다.
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

        case .verseMenuFavoriteTapped:
            guard let menu = state.verseMenu, menu.availability.canFavorite else { return .none }
            state.verseMenu = nil
            // 추가할 때 보존할 필기는 지금 보이는 필기다 — 저장 대기 중인 획까지. 해제일 때 부모는 이 값을 쓰지 않는다.
            let ink = Self.currentInk(verse: menu.verse, state: state)
            return .send(.delegate(.favoriteToggled(verse: menu.verse, ink: ink)))

        case .verseMenuHistoryTapped:
            guard let menu = state.verseMenu, menu.availability.canViewHistory else { return .none }
            state.verseMenu = nil
            state.historyAnchorFrame = menu.verseFrame
            return .send(.historyRequested(at: menu.contentPoint))

        case .verseMenuImageTapped:
            guard let menu = state.verseMenu else { return .none }
            state.verseMenu = nil
            guard let region = state.renderedLayout?.region(verse: menu.verse) else { return .none }
            // 이미지에 넣을 필기는 지금 보이는 필기다 — 저장 대기 중인 획까지, 화면처럼 현재 밑줄에 맞춘 모습으로.
            // 필기가 없어도 넘긴다 — 부모가 본문만 담은 이미지를 만든다(2026-09-15 결정).
            let ink = Self.currentInkSnapshot(verse: menu.verse, state: state).flatMap { codec.verseImageInk($0, region) }
            return .send(.delegate(.imageSaveRequested(VerseImageHandwriting(
                verse: menu.verse,
                writingSize: region.writingRect.size,
                underlineAnchors: region.underlineAnchors,
                inkData: ink
            ))))

        case .verseMenuWidgetTapped:
            guard let menu = state.verseMenu, menu.availability.canFavorite else { return .none }
            state.verseMenu = nil
            // 즐겨찾기에 없는 절이면 부모가 지금 필기 그대로 보관한 뒤 위젯 대상으로 삼는다(시안 N6).
            let widgetInk = Self.currentInk(verse: menu.verse, state: state)
            return .send(.delegate(.widgetRequested(verse: menu.verse, ink: widgetInk)))

        case .verseMenuDraftsTapped:
            guard let menu = state.verseMenu, menu.availability.hiddenDraftCount > 0 else { return .none }
            state.verseMenu = nil
            // 이 화면은 초안을 되살리지 않는다 — 보이지 않게 남은 것을 보는 자리(설정 → 남은 필기)로 보낸다(정책 §12-6 ④).
            return .send(.delegate(.draftRecoveryRequested))

        case .verseMenuEraseTapped:
            guard let menu = state.verseMenu, menu.availability.canErase else { return .none }
            state.verseMenu = nil
            return .send(.eraseRequested(at: menu.contentPoint))

        default:
            return .none
        }
    }
}
