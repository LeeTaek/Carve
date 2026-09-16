//
//  ChapterCanvasSaveFailureTesting.swift
//  CarveFeatureTest
//
//  저장 실패를 사용자에게 알린다 (로드맵 SAVE-1).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 저장이 실패해도 큐는 보존되고 다음 편집·flush 에서 자동으로 다시 시도한다(설계 §8-4).
/// 그런데 **그 사실이 화면에 전혀 드러나지 않았다** — 로그만 남았다. 사용자는 필사가 저장되지 않은 채
/// 앱을 닫을 수 있었다. 이 파일은 실패가 상태로 드러나고 재시도로 사라지는 것을 고정한다.
@Suite("저장 실패 안내")
@MainActor
struct ChapterCanvasSaveFailureTesting {
    private let newRow = CanvasTestSupport.newRow

    @Test("저장에 실패하면 알릴 상태가 되고, 재시도가 성공하면 사라진다")
    func failureSurfacesAndClearsOnRetry() async {
        let spy = RepositorySpy()
        // 첫 저장만 실패시킨다. 두 번째(재시도)는 성공한다.
        spy.applyFailures.setValue([.persistenceFailed("디스크 오류")])
        let results = LockIsolated([CanvasTestSupport.createResult("1")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)

        await store.send(.editBegan) { $0.isEditing = true }
        await store.send(.editEnded(CanvasTestSupport.edit("1"))) {
            $0.isEditing = false
            $0.editRevision = 1
            $0.editQueue = [.init(revision: 1, snapshot: CanvasTestSupport.edit("1"))]
            $0.isPreparingEdit = true
        }
        await store.receive(\.mutationsPrepared) {
            $0.isPreparingEdit = false
            $0.editQueue = []
            $0.baselineData = CanvasTestSupport.edit("1").drawingData
            $0.activeRowIDs[2] = self.newRow
            $0.pendingMutations = [self.newRow: PendingDrawingMutation(
                revision: 1, chapter: CanvasTestSupport.chapter,
                mutation: CanvasTestSupport.createResult("1").mutations[0]
            )]
            $0.saveStatus = .saving(revision: 1)
            $0.inFlightBatch = [self.newRow: 1]
            $0.inFlightMutations = CanvasTestSupport.createResult("1").mutations
            $0.inFlightChapter = CanvasTestSupport.chapter
        }

        // 실패 — 큐는 남고 상태는 failed 가 된다.
        await store.receive(\.saveFinished) {
            $0.saveStatus = .failed(revision: 1, retryCount: 1)
            $0.inFlightBatch = [:]
            $0.inFlightMutations = []
            $0.inFlightChapter = nil
        }
        #expect(store.state.saveRetryCount == 1)
        #expect(!store.state.isFullyPersisted)
        // 미저장분은 그대로다 — 알리기만 할 뿐 버리지 않는다.
        #expect(store.state.pendingMutations.count == 1)

        // 재시도. flush 가 곧 재시도 경로다 (§8-5).
        await store.send(.flushPending) {
            $0.saveStatus = .saving(revision: 1)
            $0.inFlightBatch = [self.newRow: 1]
            $0.inFlightMutations = CanvasTestSupport.createResult("1").mutations
            $0.inFlightChapter = CanvasTestSupport.chapter
        }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
            $0.inFlightBatch = [:]
            $0.inFlightMutations = []
            $0.inFlightChapter = nil
            $0.persistedRevision = 1
        }

        #expect(store.state.saveRetryCount == nil)
        #expect(store.state.isFullyPersisted)
    }

    @Test("성공한 저장은 알릴 것이 없다")
    func successHasNothingToReport() async {
        let spy = RepositorySpy()
        let results = LockIsolated([CanvasTestSupport.createResult("1")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)

        #expect(store.state.saveRetryCount == nil)
    }

    @Test("실패 횟수는 상태에서 그대로 읽힌다 — 반복 실패를 구분할 수 있어야 한다")
    func retryCountIsReadable() {
        var state = ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)

        state.saveStatus = .idle
        #expect(state.saveRetryCount == nil)

        state.saveStatus = .saving(revision: 3)
        #expect(state.saveRetryCount == nil)

        state.saveStatus = .failed(revision: 3, retryCount: 1)
        #expect(state.saveRetryCount == 1)

        state.saveStatus = .failed(revision: 3, retryCount: 4)
        #expect(state.saveRetryCount == 4)
    }
}
