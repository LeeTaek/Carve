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
            $0.saveStatus = .saving(revision: 1, requestID: UUID(1))
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
            $0.saveStatus = .saving(revision: 1, requestID: UUID(2))
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

    /// - Important: 이 테스트는 상태를 **직접** 세팅하므로 계산 프로퍼티만 본다. 실제 흐름에서 횟수가 누적되는지는
    ///              보지 못한다 — 실제로 이 테스트가 통과하는 동안 누적은 늘 1 로 돌아오는 결함이 있었다.
    ///              누적은 `failureNoticeAndQueueSurviveChapterSwitch` · `successResetsFailureCount` 가 흐름으로 확인한다.
    @Test("실패 횟수는 상태에서 그대로 읽힌다")
    func retryCountIsReadable() {
        var state = ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)

        state.saveStatus = .idle
        #expect(state.saveRetryCount == nil)

        state.saveStatus = .saving(revision: 3, requestID: UUID(1))
        #expect(state.saveRetryCount == nil)

        state.saveStatus = .failed(revision: 3, retryCount: 1)
        #expect(state.saveRetryCount == 1)

        state.saveStatus = .failed(revision: 3, retryCount: 4)
        #expect(state.saveRetryCount == 4)
    }

    // MARK: - 장 전환 중 실패

    /// 두 번째 장. 기본 장(요나 2장)과 달라야 "이전 장 항목이 현재 장으로 새는지" 를 볼 수 있다.
    private let chapterA = CanvasTestSupport.chapter
    private let chapterB = BibleChapter(title: .jonah, chapter: 3)
    private let rowInA = BibleDrawingRowID(raw: "row-in-chapter-a")
    private let rowInB = BibleDrawingRowID(raw: "row-in-chapter-b")
    private let diskError = DrawingRepositoryError.persistenceFailed("디스크 오류")

    /// 공용 헬퍼는 rowID 를 고정해 쓴다. 두 장의 편집이 같은 키로 덮이면 섞임을 검증할 수 없으므로 rowID 를 받는다.
    nonisolated private func createResult(_ tag: String, rowID: BibleDrawingRowID) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: CanvasTestSupport.layout.signature),
            mutations: [.create(verse: 2, rowID: rowID, data: Data("create-\(tag)".utf8), metadata: CanvasTestSupport.metadata())],
            issuedRowIDs: [2: rowID]
        )
    }

    /// 장 A 에서 한 획을 긋고, 그 저장이 끝날 때까지 기다린다.
    private func drawInChapterA(_ store: TestStoreOf<ChapterCanvasFeature>) async {
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
    }

    @Test("실패한 미저장분은 장을 바꿔도 남고, 재시도는 그 필사가 쓰인 장으로 간다")
    func failedPendingRetriesIntoItsOwnChapterAfterSwitch() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([diskError])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a", rowID: rowInA)]))
        await CanvasTestSupport.compose(store)

        await drawInChapterA(store)
        #expect(store.state.saveRetryCount == 1)
        #expect(store.state.pendingMutations[rowInA]?.chapter == chapterA)

        // 장 전환은 flush 지점이다 — 실패한 batch 를 다시 시도한다 (§8-5).
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        await store.receive(\.saveFinished)

        #expect(store.state.chapter == chapterB)
        // ★ 재시도가 **이전 장**으로 갔다. 현재 장(B)으로 가면 필사가 다른 장에 붙는다.
        #expect(spy.applied.value.map(\.chapter) == [chapterA, chapterA])
        #expect(spy.applied.value.last?.mutations.map(\.rowID) == [rowInA])
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.saveRetryCount == nil)
    }

    @Test("장을 바꾼 뒤 재시도도 실패하면 안내와 큐가 그대로 남는다 — 장 전환이 실패를 지우지 않는다")
    func failureNoticeAndQueueSurviveChapterSwitch() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([diskError, diskError])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a", rowID: rowInA)]))
        await CanvasTestSupport.compose(store)

        await drawInChapterA(store)
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        await store.receive(\.saveFinished)

        #expect(store.state.chapter == chapterB)
        // 안내가 남아 있어야 사용자가 새 장에서도 저장되지 않은 필사가 있다는 것을 안다.
        #expect(store.state.saveRetryCount == 2)
        // 미저장분은 버려지지 않았고, 여전히 **장 A** 의 것이다.
        #expect(store.state.pendingMutations.count == 1)
        #expect(store.state.pendingMutations[rowInA]?.chapter == chapterA)
        #expect(spy.applied.value.map(\.chapter) == [chapterA, chapterA])
    }

    @Test("저장이 도는 중에 장을 바꾸고 그 저장이 실패해도 항목은 이전 장 것으로 남고, 다음 재시도도 이전 장으로 간다")
    func inFlightFailureDuringSwitchKeepsItsChapter() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([diskError])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a", rowID: rowInA)]))
        await CanvasTestSupport.compose(store)

        spy.holdNextApply()
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.saveStatus == .saving(revision: 1, requestID: UUID(1)))

        // 저장이 붙잡힌 채로 장을 바꾼다. 도는 저장이 있으므로 장 전환의 flush 는 새 저장을 시작하지 않는다.
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        #expect(store.state.chapter == chapterB)
        #expect(store.state.inFlightChapter == chapterA)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 1)
        #expect(store.state.inFlightChapter == nil)
        #expect(store.state.pendingMutations[rowInA]?.chapter == chapterA)

        // 사용자가 새 장에서 「다시 시도」 를 눌러도 이전 장으로 저장된다.
        await store.send(.flushPending)
        await store.receive(\.saveFinished)
        #expect(spy.applied.value.map(\.chapter) == [chapterA, chapterA])
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.saveRetryCount == nil)
    }

    @Test("실패한 이전 장 항목과 새 장 편집은 한 번의 저장에 섞이지 않고 각자의 장으로, 이전 장부터 간다")
    func previousAndNewChapterEditsNeverShareABatch() async {
        let spy = RepositorySpy()
        // ① 장 A 편집 저장 실패 ② 장 전환 재시도 실패 — 그 뒤로는 성공
        spy.applyFailures.setValue([diskError, diskError])
        let results = LockIsolated([createResult("a", rowID: rowInA), createResult("b", rowID: rowInB)])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)
        await drawInChapterA(store)

        // 장 B 조회를 붙잡아, 장 전환의 재시도가 먼저 끝나게 순서를 고정한다.
        spy.holdNextLoadCall()
        await store.send(.load(chapter: chapterB, expectedVerseCount: 3))
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 2)
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(store.state.isComposed)

        // 실패 상태에서 새 장에 한 획을 긋는다. 새 편집은 저장을 다시 시작하고, 이전 장 batch 가 먼저 간다.
        let generation = store.state.renderedRevision
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("b", generation: generation)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        await store.receive(\.saveFinished)

        let applied = spy.applied.value
        #expect(applied.map(\.chapter) == [chapterA, chapterA, chapterA, chapterB])
        // ★ 어느 호출도 두 장의 행을 함께 담지 않는다 — 한 번의 저장은 한 장이다.
        for call in applied {
            let rows = Set(call.mutations.map(\.rowID))
            #expect(rows == (call.chapter == chapterA ? [rowInA] : [rowInB]))
        }
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.saveRetryCount == nil)
    }

    @Test("실패는 재시도를 거쳐도 누적되고, 성공하면 초기화된다 — 그 뒤 실패는 다시 첫 실패다")
    func successResetsFailureCount() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([diskError, diskError])
        let results = LockIsolated([createResult("a", rowID: rowInA), createResult("b", rowID: rowInB)])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)

        await drawInChapterA(store)
        #expect(store.state.saveRetryCount == 1)

        // 재시도는 `.saving` 을 거친다. 이전 구현은 여기서 횟수가 1 로 돌아왔다.
        await store.send(.flushPending)
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 2)

        await store.send(.flushPending)
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == nil)
        #expect(store.state.consecutiveSaveFailures == 0)

        // 성공 뒤의 실패는 이어진 실패가 아니다.
        spy.applyFailures.setValue([diskError])
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.saveRetryCount == 1)
    }
}

// MARK: - 저장 상태 표시 판정

/// 로컬 저장 상태 표시(로드맵 SAVE-1)의 판정 규칙. 표시 방식과 분리해 흐름으로 고정한다.
@Suite("저장 상태 표시 판정")
@MainActor
struct LocalSaveIndicatorTesting {
    private let rowInA = BibleDrawingRowID(raw: "row-in-chapter-a")
    private let diskError = DrawingRepositoryError.persistenceFailed("디스크 오류")

    nonisolated private func createResult(_ tag: String) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: CanvasTestSupport.layout.signature),
            mutations: [.create(verse: 2, rowID: BibleDrawingRowID(raw: "row-in-chapter-a"), data: Data("create-\(tag)".utf8), metadata: CanvasTestSupport.metadata())],
            issuedRowIDs: [2: BibleDrawingRowID(raw: "row-in-chapter-a")]
        )
    }

    @Test("아직 아무것도 쓰지 않았으면 표시하지 않는다 — 저장할 것이 없었는데 저장됐다고 말하지 않는다")
    func nothingWrittenShowsNothing() async {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy())
        await CanvasTestSupport.compose(store)

        #expect(store.state.localSaveIndicator == .none)
    }

    @Test("획을 긋는 중 → 대기 중 → 저장 중 → 이 기기에 저장됨 순서로 간다")
    func progressesThroughEachState() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a")]))
        await CanvasTestSupport.compose(store)

        await store.send(.editBegan)
        // 펜이 닿아 있다. 이 획은 아직 보고되지도 않았다.
        #expect(store.state.localSaveIndicator == .pending)

        spy.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        // 코덱이 저장 명령을 만드는 중이다.
        #expect(store.state.localSaveIndicator == .pending)

        await store.receive(\.mutationsPrepared)
        #expect(store.state.localSaveIndicator == .saving)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .saved)
    }

    @Test("변경 없이 도구를 뗀 것은 저장 상태를 바꾸지 않는다")
    func cancelledEditLeavesSavedAlone() async {
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy(), results: LockIsolated([createResult("a")]))
        await CanvasTestSupport.compose(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .saved)

        await store.send(.editBegan)
        #expect(store.state.localSaveIndicator == .pending)
        await store.send(.editCancelled)
        #expect(store.state.localSaveIndicator == .saved)
    }

    @Test("실패는 가장 먼저 보인다 — 실패한 채로 새 획을 긋고 있어도 실패 안내를 내리지 않는다")
    func failureOutranksEditing() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([diskError])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a")]))
        await CanvasTestSupport.compose(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .failed(retryCount: 1))

        await store.send(.editBegan)
        #expect(store.state.localSaveIndicator == .failed(retryCount: 1))
    }

    @Test("장을 바꿔도 이전 장의 저장이 도는 중이면 저장 중이다 — 새 장에 쓴 것이 없어도 조용해지지 않는다")
    func previousChapterPendingKeepsIndicatorPending() async {
        let spy = RepositorySpy()
        spy.holdNextApply()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([createResult("a")]))
        await CanvasTestSupport.compose(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.localSaveIndicator == .saving)

        await store.send(.load(chapter: BibleChapter(title: .jonah, chapter: 3), expectedVerseCount: 3))
        // 도는 저장이 있어 새 장에서도 "저장 중" 이다 — 장이 바뀌었다고 조용해지지 않는다.
        #expect(store.state.localSaveIndicator == .saving)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .saved)
    }

    @Test("필사 데이터를 전부 지우면 '저장됨' 을 내리고, 그 뒤 새로 쓰면 다시 보인다")
    func externalClearWithdrawsSavedUntilNextEdit() async {
        let results = LockIsolated([createResult("a"), createResult("b")])
        let store = CanvasTestSupport.makeStore(spy: RepositorySpy(), results: results)
        await CanvasTestSupport.compose(store)
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .saved)

        // 설정에서 전부 지웠다. 저장된 필사가 없는데 "저장됨" 이라고 말하면 안 된다.
        await store.send(.drawingDataCleared)
        #expect(store.state.localSaveIndicator == .none)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.localSaveIndicator == .none)

        // 지운 뒤에 새로 쓴 것은 다시 "저장됨" 이다.
        let generation = store.state.renderedRevision
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("b", generation: generation)))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(store.state.localSaveIndicator == .saved)
    }
}
