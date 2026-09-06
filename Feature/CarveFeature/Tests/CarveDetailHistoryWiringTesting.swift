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
