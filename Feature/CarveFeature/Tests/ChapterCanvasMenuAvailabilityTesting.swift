//
//  ChapterCanvasMenuAvailabilityTesting.swift
//  CarveFeatureTest
//
//  UI-2 — 롱탭 메뉴는 **할 수 있는 것만** 띄운다.
//  · "이전 필사 내용 보기" 는 대표가 아닌 행이 있을 때만
//  · "지우기" 는 그 절에 획이 있을 때만 (저장 대기 중인 획 포함)
//  · 둘 다 없으면 메뉴 자체를 올리지 않는다
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("UI-2 — 롱탭 메뉴 가용성")
@MainActor
struct ChapterCanvasMenuAvailabilityTesting {
    private static let verse = 1
    /// 절 1 의 필사 영역 안 (uniformLayout: v1 = y [0, 30)).
    private static let pointInVerse = CGPoint(x: 10, y: 15)
    private static let archiveRow = BibleDrawingRowID(raw: "row-archive")

    /// 실제 획이 하나 있는 `PKDrawing` 데이터. `containsPKStroke` 가 참이 되는 유일한 형태다 —
    /// 길이만 있는 `Data([1])` 은 디코딩에 실패해 "획 없음" 으로 판정된다.
    private static func inkData() -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: 5, y: 5), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    private static func snapshot(
        rowID: BibleDrawingRowID,
        isPresent: Bool,
        lineData: Data?,
        updateDate: Date?
    ) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(verse: verse, rowID: rowID, isPresent: isPresent,
                             updateDate: updateDate, lineData: lineData,
                             drawingVersion: 3, metadata: nil)
    }

    /// 합성까지 마친 상태를 복사해 그 절의 행 목록을 원하는 모양으로 갈아 끼운다.
    /// `TestStore.state` 는 읽기 전용이지만 `State` 는 값 타입이라 사본을 만들면 된다.
    private func composedState(rows: [VerseDrawingSnapshot]) async -> ChapterCanvasFeature.State {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)
        var state = store.state
        state.loadedDrawings = rows
        return state
    }

    @Test("획도 지난 회차도 없으면 띄울 항목이 없다 — 메뉴를 올리지 않는다")
    func nothingToOfferOnUntouchedVerse() async {
        let state = await composedState(rows: [])

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(availability.isEmpty)
        #expect(!availability.canViewHistory)
        #expect(!availability.canErase)
    }

    @Test("쓰기만 한 절 — 지우기만 띄운다. 회차가 하나뿐이면 '이전 필사' 가 아니다")
    func writtenOnceOffersEraseOnly() async {
        let state = await composedState(rows: [
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                          lineData: Self.inkData(), updateDate: Date(timeIntervalSince1970: 100))
        ])

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(availability.canErase)
        #expect(!availability.canViewHistory)
    }

    @Test("지우기 후 — 이전 필사만 띄운다. 활성 행은 비었고 보관본이 남는다")
    func afterEraseOffersHistoryOnly() async {
        let state = await composedState(rows: [
            // 활성(대표) 행: 비었고 갱신이 최신
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                          lineData: nil, updateDate: Date(timeIntervalSince1970: 200)),
            // 보관본: 내용이 있고 대표가 아니다
            Self.snapshot(rowID: Self.archiveRow, isPresent: false,
                          lineData: Self.inkData(), updateDate: Date(timeIntervalSince1970: 100))
        ])

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(availability.canViewHistory)
        #expect(!availability.canErase)
    }

    @Test("저장 대기 중인 획도 지우기 대상이다 — 저장분만 보면 방금 쓴 절에서 항목이 사라진다")
    func pendingInkCountsAsErasable() async {
        var state = await composedState(rows: [
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                          lineData: nil, updateDate: Date(timeIntervalSince1970: 100))
        ])
        // DB 에는 아직 없고 큐에만 있는 획.
        state.pendingMutations[CanvasTestSupport.rowA] = PendingDrawingMutation(
            revision: 1,
            chapter: CanvasTestSupport.chapter,
            mutation: .replace(verse: Self.verse, rowID: CanvasTestSupport.rowA,
                               data: Self.inkData(), metadata: CanvasTestSupport.metadata())
        )

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(availability.canErase)
    }

    @Test("대기 중인 명령이 비우기면 지우기를 띄우지 않는다 — 저장분이 남아 있어도")
    func pendingClearHidesErase() async {
        var state = await composedState(rows: [
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                          lineData: Self.inkData(), updateDate: Date(timeIntervalSince1970: 100))
        ])
        state.pendingMutations[CanvasTestSupport.rowA] = PendingDrawingMutation(
            revision: 1,
            chapter: CanvasTestSupport.chapter,
            mutation: .clear(verse: Self.verse, rowID: CanvasTestSupport.rowA)
        )

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(!availability.canErase)
    }

    @Test("합성 전에는 절을 알 수 없으므로 아무 항목도 띄우지 않는다")
    func noMenuBeforeCompose() {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: store.state)

        #expect(availability.isEmpty)
    }

    @Test("비대표 행이 있어도 **내용이 없으면** 이전 필사를 띄우지 않는다 — 목록의 필터와 같은 기준")
    func emptyNonRepresentativeRowDoesNotOfferHistory() async {
        // 대표(현재 필사)는 그대로 두고 **비대표 행의 내용만** 뒤집어 양방향을 함께 본다.
        func rows(nonRepresentative lineData: Data?) -> [VerseDrawingSnapshot] {
            [
                Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                              lineData: Self.inkData(), updateDate: Date(timeIntervalSince1970: 300)),
                Self.snapshot(rowID: Self.archiveRow, isPresent: false,
                              lineData: lineData, updateDate: Date(timeIntervalSince1970: 100))
            ]
        }

        // 빈 행뿐이면 목록에 그릴 것이 없다 → 항목을 띄우지 않는다.
        let emptyState = await composedState(rows: rows(nonRepresentative: nil))
        #expect(!ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: emptyState).canViewHistory)

        // 같은 자리에 내용이 들어오면 띄운다 (양성 대조 — 조건이 항상 거짓이 된 게 아니다).
        let carvedState = await composedState(rows: rows(nonRepresentative: Self.inkData()))
        #expect(ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: carvedState).canViewHistory)
    }

    @Test("보관본을 골라 대표가 뒤바뀌면 이전 필사를 숨긴다 — 메뉴와 목록이 어긋나던 자리")
    func selectingArchiveHidesHistoryWhenOnlyEmptyRowRemains() async {
        // 지우기 → [빈 활성(대표), 보관본] 에서 사용자가 "이전 필사 내용 보기" 로 보관본을 골랐다.
        // `updatePresentDrawing` 이 isPresent 를 보관본으로 옮기므로 대표가 보관본이 되고,
        // **빈 행이 비대표로** 남는다. 행 존재만 보면 여기서 메뉴는 항목을 띄우는데 목록은 비어 있었다.
        let rows = [
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: false,
                          lineData: nil, updateDate: Date(timeIntervalSince1970: 200)),
            Self.snapshot(rowID: Self.archiveRow, isPresent: true,
                          lineData: Self.inkData(), updateDate: Date(timeIntervalSince1970: 100))
        ]
        let state = await composedState(rows: rows)

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        // 전제 — 대표가 보관본으로 넘어갔다. (넘어가지 않았다면 이 테스트는 다른 것을 재는 셈이다)
        #expect(rows.representative()?.rowID == Self.archiveRow)
        #expect(!availability.canViewHistory)
        // 대표에 획이 있으니 지우기는 그대로 띄운다 — 메뉴가 통째로 사라진 게 아니다.
        #expect(availability.canErase)
    }

    @Test("획이 있어도 디코딩되지 않는 데이터면 지우기를 띄우지 않는다")
    func undecodableDataIsNotErasable() async {
        // 지우개로 전부 지운 절은 lineData 가 남아 있어도 stroke 가 0개다. 길이로 판정하면 틀린다.
        let state = await composedState(rows: [
            Self.snapshot(rowID: CanvasTestSupport.rowA, isPresent: true,
                          lineData: Data([1, 2, 3]), updateDate: Date(timeIntervalSince1970: 100))
        ])

        let availability = ChapterCanvasFeature.menuAvailability(at: Self.pointInVerse, state: state)

        #expect(!availability.canErase)
    }
}
