//
//  CarveDetailHistoryWiringTesting.swift
//  CarveFeatureTest
//
//  Phase 3 (3/3) — B 구조의 히스토리 UI 배선 (설계 §8-7 "히스토리 복원 흐름").
//  `CarveDetailFeature.State` 는 Equatable 이 아니라 TestStore 대신 실제 Store 로 상태 전이를 본다.
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@Suite("Phase 3 — CarveDetailFeature · 단일 Canvas 히스토리 배선 (3/3)")
@MainActor
struct CarveDetailHistoryWiringTesting {
    private func makeStore(spy: RepositorySpy) -> StoreOf<CarveDetailFeature> {
        Store(initialState: CarveDetailFeature.State.initialState) {
            CarveDetailFeature()
        } withDependencies: {
            $0.drawingRepository = spy
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
    }

    @Test("캔버스의 히스토리 요청은 그 절의 시트를 열고, 회차 선택은 시트를 닫은 뒤 mutation 없이 다시 합성한다 (§8-7 ③)")
    func historyRequestOpensSheetAndSelectionRecomposes() async throws {
        let spy = RepositorySpy()
        let store = makeStore(spy: spy)
        let chapter = store.chapterCanvas.chapter

        store.send(.scope(.chapterCanvasAction(.delegate(.showHistory(verse: 2)))))
        #expect(store.chapterHistory?.verse == 2)
        #expect(store.chapterHistory?.title == chapter)

        // 시트가 isPresent 를 옮긴 뒤 알린다 (②). 여기서는 ③ 만 확인한다.
        let restored = BibleDrawing(bibleTitle: chapter, verse: 2)
        store.send(.chapterHistory(.presented(.setPresentDrawing(restored))))
        #expect(store.chapterHistory == nil)
        // verseRowRestored → 미저장분 없음 → 곧바로 DB 재조회 (재합성 대기).
        #expect(store.chapterCanvas.isReloading)
        try await Task.sleep(for: .milliseconds(100))
        #expect(spy.loadedChapters.value == [chapter])
        #expect(spy.applied.value.isEmpty)   // 복원은 저장 명령을 만들지 않는다
    }

    @Test("시트를 그냥 닫으면 아무 일도 없다")
    func dismissingSheetDoesNothing() async throws {
        let spy = RepositorySpy()
        let store = makeStore(spy: spy)

        store.send(.scope(.chapterCanvasAction(.delegate(.showHistory(verse: 1)))))
        store.send(.chapterHistory(.dismiss))
        #expect(store.chapterHistory == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(spy.loadedChapters.value.isEmpty)
        #expect(!store.chapterCanvas.isReloading)
    }
}

// MARK: - 목록 자체 (§8-7 "빈 행은 히스토리 목록에서만 숨긴다")

/// 시트의 목록 상태에 무엇이 담기는지. 저장소 조회는 그대로 두고 **`setDrawings` 한 곳에서만** 거른다.
///
/// `setDrawings` 는 효과가 없는 상태 전이라 DB 를 거치지 않고 확인한다. 공유 인메모리 저장소
/// (`DrawingDatabase.testValue`)를 건드리면 그 저장소를 함께 쓰는 다른 스위트의 실행 순서에 영향을 준다 —
/// `DrawingErasePersistenceTesting` 은 `@Dependency(\.modelContainer)` 로 검증용 context 를 만들어
/// **누가 먼저 저장소를 초기화하는지에 민감하다.** 저장소를 실제로 거치는 조회는 Domain 쪽
/// `DrawingHistoryRowsTesting` 이 격리된 컨테이너로 본다.
@Suite("UI-2 후속 — 히스토리 목록은 빈 행을 담지 않는다")
@MainActor
struct VerseDrawingHistoryListWiringTesting {
    private static let chapter = BibleChapter(title: .habakkuk, chapter: 3)
    private static let verse = 4

    /// 실제 획이 하나 있는 `PKDrawing` 데이터. 길이만 있는 `Data([1, 2, 3])` 은 디코딩에 실패해 "획 없음" 이다.
    private static func inkData() -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: 5, y: 5), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }

    private static func row(rowUUID: String, lineData: Data?, updateDate: Date, isPresent: Bool) -> BibleDrawing {
        let row = BibleDrawing(bibleTitle: chapter, verse: verse, lineData: lineData,
                               updateDate: updateDate, rowUUID: rowUUID)
        row.isPresent = isPresent
        return row
    }

    @Test("지우기가 남긴 빈 활성 행은 목록에 담기지 않는다 — 보관본만 남는다")
    func emptyActiveRowIsNotListed() {
        // 지우기 직후의 모양. 저장소는 `updateDate` 내림차순으로 주므로 빈 활성 행이 **맨 위**로 온다.
        let active = Self.row(rowUUID: "row-active", lineData: nil,
                              updateDate: Date(timeIntervalSince1970: 900), isPresent: true)
        let archived = Self.row(rowUUID: "row-archive", lineData: Self.inkData(),
                                updateDate: Date(timeIntervalSince1970: 100), isPresent: false)
        let store = Store(initialState: VerseDrawingHistoryFeature.State(title: Self.chapter, verse: Self.verse)) {
            VerseDrawingHistoryFeature()
        }

        store.send(.setDrawings([active, archived]))

        #expect(store.drawings.map(\.rowKey) == ["row-archive"])
    }

    @Test("내용이 있는 회차는 순서 그대로 전부 담는다 — 조건이 항상 거짓이 된 게 아니다")
    func carvedRowsAreAllListedInOrder() {
        let newer = Self.row(rowUUID: "row-newer", lineData: Self.inkData(),
                             updateDate: Date(timeIntervalSince1970: 900), isPresent: true)
        let older = Self.row(rowUUID: "row-older", lineData: Self.inkData(),
                             updateDate: Date(timeIntervalSince1970: 100), isPresent: false)
        let store = Store(initialState: VerseDrawingHistoryFeature.State(title: Self.chapter, verse: Self.verse)) {
            VerseDrawingHistoryFeature()
        }

        store.send(.setDrawings([newer, older]))

        #expect(store.drawings.map(\.rowKey) == ["row-newer", "row-older"])
    }
}
