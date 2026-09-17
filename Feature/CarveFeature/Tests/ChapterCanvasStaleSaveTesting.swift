//
//  ChapterCanvasStaleSaveTesting.swift
//  CarveFeatureTest
//
//  늦게 도착한 저장 완료 응답 (리뷰 P1-1).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 모든 저장을 **호출 순서대로** 붙잡아 두고, 고른 것만 풀어 준다.
///
/// 공용 `RepositorySpy` 는 게이트가 하나라 두 번째 저장이 첫 번째 게이트를 덮는다. 진행 중인 저장 둘이
/// 겹치는 순서를 재현하려면 각각을 따로 붙잡아야 한다.
private final class OrderedApplySpy: DrawingRepository, @unchecked Sendable {
    private let gates = LockIsolated<[Int: AsyncStream<Void>.Continuation]>([:])
    private let nextIndex = LockIsolated(0)
    let applied = LockIsolated<[[VerseDrawingMutation]]>([])

    func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot] { [] }

    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws {
        let index = nextIndex.withValue { value -> Int in
            defer { value += 1 }
            return value
        }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gates.withValue { $0[index] = continuation }
        for await _ in stream { break }
        applied.withValue { $0.append(mutations) }
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
        .alreadyEmpty
    }

    /// `index` 번째로 호출된 저장을 끝낸다.
    func release(_ index: Int) {
        gates.withValue { gates in
            gates[index]?.yield()
            gates[index]?.finish()
            gates[index] = nil
        }
    }
}

@Suite("늦게 도착한 저장 완료")
@MainActor
struct ChapterCanvasStaleSaveTesting {
    private let rowA = BibleDrawingRowID(raw: "row-before-clear")
    private let rowB = BibleDrawingRowID(raw: "row-after-clear")

    nonisolated private func createResult(_ tag: String, rowID: BibleDrawingRowID) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: CanvasTestSupport.layout.signature),
            mutations: [.create(verse: 2, rowID: rowID, data: Data("create-\(tag)".utf8), metadata: CanvasTestSupport.metadata())],
            issuedRowIDs: [2: rowID]
        )
    }

    private func makeStore(_ spy: OrderedApplySpy, results: [DrawingEditResult]) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results))
            $0.drawingRepository = spy
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    /// ★ 리뷰가 짚은 순서. 전체 삭제로 상태를 비운 뒤 새 저장이 시작됐는데, 삭제 **전에** 시작한 저장의 완료 응답이
    /// 늦게 도착한다. 그 응답은 자기 저장이 아니라 **지금 도는 저장의** 기록을 가져가 처리했다 —
    /// 아직 저장되지 않은 새 필사를 큐에서 지우는 경로다.
    @Test("삭제 전에 시작한 저장의 완료 응답은 삭제 뒤에 시작한 저장의 기록을 건드리지 않는다")
    func staleCompletionDoesNotTouchCurrentSave() async {
        let spy = OrderedApplySpy()
        let store = makeStore(spy, results: [createResult("a", rowID: rowA), createResult("b", rowID: rowB)])
        await CanvasTestSupport.compose(store)

        // 저장 A — 붙잡힌 채로 둔다.
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.inFlightBatch.keys.contains(rowA))

        // 설정에서 전부 지웠다. 열린 장은 큐와 진행 중 기록을 비우고 다시 합성한다.
        await store.send(.drawingDataCleared)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isComposed)

        // 저장 B — 삭제 뒤에 쓴 새 필사. 이것도 붙잡는다.
        let generation = store.state.renderedRevision
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("b", generation: generation)))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.inFlightBatch.keys.contains(rowB))
        #expect(store.state.pendingMutations[rowB] != nil)

        // A 가 이제서야 끝난다.
        spy.release(0)
        await store.receive(\.saveFinished)

        // B 는 아직 저장되지 않았다. 큐에서 사라지거나 진행 중 기록이 비면 안 된다.
        #expect(store.state.pendingMutations[rowB] != nil)
        #expect(store.state.inFlightBatch.keys.contains(rowB))
        #expect(!store.state.isFullyPersisted)
        guard case .saving = store.state.saveStatus else {
            Issue.record("B 가 도는 중인데 저장 상태가 \(store.state.saveStatus) 로 바뀌었다")
            return
        }

        // B 가 끝나야 비로소 저장 완료다.
        spy.release(1)
        await store.receive(\.saveFinished)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.isFullyPersisted)
    }
}
