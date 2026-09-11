//
//  ChapterCanvasVerseMenuTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 9/11/26.
//
//  절 롱탭 메뉴(시안 E1) — 메뉴를 여닫는 상태와, 항목이 기존 흐름(지우기 확인 · 필사 기록)으로 이어지는지.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("E1 — 절 롱탭 메뉴")
@MainActor
struct ChapterCanvasVerseMenuTesting {
    /// 절 1 의 필사 영역 안 (uniformLayout: v1 = y [0, 30)).
    private static let pointInVerse = CGPoint(x: 10, y: 15)
    private static let verseFrame = CGRect(x: 0, y: 200, width: 800, height: 60)

    private static func inkData() -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: 5, y: 5), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }

    private func composedState(withInk: Bool) async -> ChapterCanvasFeature.State {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)
        var state = store.state
        state.loadedDrawings = withInk ? [
            VerseDrawingSnapshot(verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true,
                                 updateDate: Date(timeIntervalSince1970: 100), lineData: Self.inkData(),
                                 drawingVersion: 3, metadata: nil)
        ] : []
        return state
    }

    @Test("아무것도 할 수 없는 절은 메뉴를 열지 않는다 (UI-2)")
    func untouchedVerseOpensNoMenu() async {
        var state = await composedState(withInk: false)

        _ = ChapterCanvasFeature().reduce(
            into: &state,
            action: .verseMenuRequested(at: Self.pointInVerse, anchor: .zero, verseFrame: Self.verseFrame)
        )

        #expect(state.verseMenu == nil)
    }

    @Test("획이 있는 절은 메뉴가 열리고, 「지우기」 를 고르면 메뉴가 닫히며 지우기 확인으로 이어진다")
    func eraseItemClosesMenuAndAsksForConfirmation() async {
        let initialState = await composedState(withInk: true)
        let store = TestStore(initialState: initialState) {
            ChapterCanvasFeature()
        }
        store.exhaustivity = .off

        await store.send(.verseMenuRequested(at: Self.pointInVerse, anchor: CGPoint(x: 120, y: 230), verseFrame: Self.verseFrame))
        #expect(store.state.verseMenu?.verse == 1)
        #expect(store.state.verseMenu?.verseFrame == Self.verseFrame)
        #expect(store.state.verseMenu?.availability.canErase == true)

        await store.send(.verseMenuEraseTapped)
        await store.receive(\.eraseRequested)
        #expect(store.state.verseMenu == nil)
        #expect(store.state.eraseAlert != nil)
    }

    @Test("가림막을 누르면 메뉴만 닫히고 다른 상태는 그대로다")
    func dismissOnlyClosesMenu() async {
        var state = await composedState(withInk: true)
        _ = ChapterCanvasFeature().reduce(
            into: &state,
            action: .verseMenuRequested(at: Self.pointInVerse, anchor: .zero, verseFrame: Self.verseFrame)
        )
        #expect(state.verseMenu != nil)

        _ = ChapterCanvasFeature().reduce(into: &state, action: .verseMenuDismissed)

        #expect(state.verseMenu == nil)
        #expect(state.eraseAlert == nil)
    }
}
