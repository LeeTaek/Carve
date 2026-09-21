//
//  ChapterCanvasVerseImageMenuTesting.swift
//  CarveFeatureTest
//
//  절 메뉴 「이미지 저장」(시안 G1) — 메뉴가 닫히고, 그 절의 필사 영역 · 밑줄과 지금 보이는 필기를 부모에 넘기는지.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("G1 — 절 메뉴 「이미지 저장」")
@MainActor
struct ChapterCanvasVerseImageMenuTesting {
    /// 절 1 의 필사 영역 안 (uniformLayout: v1 = y [0, 30)).
    private static let pointInVerse = CGPoint(x: 10, y: 15)
    private static let verseFrame = CGRect(x: 0, y: 200, width: 800, height: 60)

    private static func inkData(x: CGFloat = 5) -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: x, y: 5), timeOffset: 0,
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

    /// 코덱은 받은 행을 기록하고 행 id 로 구분되는 필기를 돌려준다.
    private func makeStore(
        _ state: ChapterCanvasFeature.State,
        inkInputs: LockIsolated<[VerseDrawingSnapshot]>
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: state) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.drawingCodec.verseImageInk = { snapshot, _ in
                inkInputs.withValue { $0.append(snapshot) }
                return Data("ink-\(snapshot.rowID.raw)".utf8)
            }
        }
        store.exhaustivity = .off
        return store
    }

    @Test("고르면 메뉴가 닫히고, 그 절의 필사 영역 · 밑줄과 지금 필기를 부모에 넘긴다")
    func imageItemClosesMenuAndDelegatesHandwriting() async throws {
        let initialState = await composedState(withInk: true)
        let region = try #require(initialState.renderedLayout?.region(verse: 1))
        let inkInputs = LockIsolated<[VerseDrawingSnapshot]>([])
        let store = makeStore(initialState, inkInputs: inkInputs)

        await store.send(.verseMenuRequested(at: Self.pointInVerse, anchor: CGPoint(x: 120, y: 230), verseFrame: Self.verseFrame))
        await store.send(.verseMenuImageTapped)
        await store.receive(.delegate(.imageSaveRequested(VerseImageHandwriting(
            verse: 1,
            writingSize: region.writingRect.size,
            underlineAnchors: region.underlineAnchors,
            inkData: Data("ink-\(CanvasTestSupport.rowA.raw)".utf8)
        ))))

        #expect(store.state.verseMenu == nil)
        #expect(inkInputs.value.map(\.rowID) == [CanvasTestSupport.rowA])
    }

    @Test("필기가 없는 절도 넘긴다 — 필기 없이(본문만 담는 이미지)")
    func verseWithoutInkDelegatesWithoutHandwriting() async throws {
        let initialState = await composedState(withInk: false)
        let region = try #require(initialState.renderedLayout?.region(verse: 1))
        let inkInputs = LockIsolated<[VerseDrawingSnapshot]>([])
        let store = makeStore(initialState, inkInputs: inkInputs)

        await store.send(.verseMenuRequested(at: Self.pointInVerse, anchor: .zero, verseFrame: Self.verseFrame))
        await store.send(.verseMenuImageTapped)
        await store.receive(.delegate(.imageSaveRequested(VerseImageHandwriting(
            verse: 1,
            writingSize: region.writingRect.size,
            underlineAnchors: region.underlineAnchors,
            inkData: nil
        ))))

        #expect(inkInputs.value.isEmpty)
    }

    @Test("저장 대기 중인 편집이 이긴다 — 방금 쓴 획을 저장될 모습(v3 · 현재 metadata)으로 코덱에 넘긴다")
    func pendingEditIsUsedForImage() async throws {
        var initialState = await composedState(withInk: true)
        let pending = Self.inkData(x: 40)
        initialState.pendingMutations[CanvasTestSupport.rowA] = PendingDrawingMutation(
            revision: 1,
            chapter: CanvasTestSupport.chapter,
            mutation: .replace(verse: 1, rowID: CanvasTestSupport.rowA, data: pending, metadata: CanvasTestSupport.metadata())
        )
        let inkInputs = LockIsolated<[VerseDrawingSnapshot]>([])
        let store = makeStore(initialState, inkInputs: inkInputs)

        await store.send(.verseMenuRequested(at: Self.pointInVerse, anchor: .zero, verseFrame: Self.verseFrame))
        await store.send(.verseMenuImageTapped)
        // Delegate 는 CasePathable 이 아니라 key path 로 받을 수 없다 — 기대 값을 그대로 적는다.
        let region = try #require(initialState.renderedLayout?.region(verse: 1))
        await store.receive(.delegate(.imageSaveRequested(VerseImageHandwriting(
            verse: 1,
            writingSize: region.writingRect.size,
            underlineAnchors: region.underlineAnchors,
            inkData: Data("ink-\(CanvasTestSupport.rowA.raw)".utf8)
        ))))

        #expect(inkInputs.value == [VerseDrawingSnapshot(
            verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true, updateDate: nil,
            lineData: pending, drawingVersion: 3, metadata: CanvasTestSupport.metadata()
        )])
    }
}
