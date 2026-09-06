//
//  ChapterCanvasFeatureTesting.swift
//  CarveFeatureTest
//
//  Phase 3 — ChapterCanvasFeature: §6-4 합성 게이트 · §8-1 편집 계약 · §8-3 coalescing/직렬 저장 · §8-4 실패 · §8-7 복원
//  코덱과 저장소를 스텁으로 바꿔 상태 전이만 고정한다. 설계 §14 의 5-2 · 5-3 · 5-7 · 6 · 6-1 · 6-2 · 6-3 · 7 · 8 · 10 · 11.
//  rev.17 — 편집 세대(generation) · 물러난 세션 · 편집 중 보류 · 재합성 게이트 출구 · coalesce (clear, replace) · 스크롤 토큰.
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

// MARK: - 스텁

/// 호출을 기록하고, 필요하면 저장을 게이트로 붙잡아 두는 저장소.
final class RepositorySpy: DrawingRepository, @unchecked Sendable {
    let loadedChapters = LockIsolated<[BibleChapter]>([])
    let applied = LockIsolated<[(chapter: BibleChapter, mutations: [VerseDrawingMutation])]>([])
    /// nil 이면 즉시 성공. 값이 있으면 그 스트림에서 신호가 올 때까지 저장을 붙잡는다.
    let applyGate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)
    let applyFailures = LockIsolated<[DrawingRepositoryError]>([])
    /// 순서대로 소비되는 조회 실패 메시지. 비어 있으면 성공. (Feature 는 `"\(error)"` 를 메시지로 옮기므로 설명이 곧 메시지인 오류를 던진다.)
    let loadFailures = LockIsolated<[String]>([])
    struct LoadBoom: Error, CustomStringConvertible { let description: String }
    var snapshots: @Sendable (BibleChapter) -> [VerseDrawingSnapshot] = { _ in [] }

    func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot] {
        if let (stream, continuation) = makeLoadGateIfNeeded() {
            loadGate.setValue(continuation)
            for await _ in stream { break }
        }
        loadedChapters.withValue { $0.append(chapter) }
        if let message = loadFailures.withValue({ $0.isEmpty ? nil : $0.removeFirst() }) {
            throw LoadBoom(description: message)
        }
        return snapshots(chapter)
    }

    /// 다음 `load` 를 `releaseLoad()` 까지 붙잡는다 — 늦게 도착하는 조회 결과를 재현하기 위함.
    private let holdNextLoad = LockIsolated(false)
    let loadGate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)
    func holdNextLoadCall() { holdNextLoad.setValue(true) }
    func releaseLoad() {
        loadGate.withValue { $0?.yield(); $0?.finish(); $0 = nil }
    }
    private func makeLoadGateIfNeeded() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation)? {
        guard holdNextLoad.withValue({ let value = $0; $0 = false; return value }) else { return nil }
        return AsyncStream<Void>.makeStream()
    }

    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws {
        if let (stream, continuation) = makeGateIfNeeded() {
            applyGate.setValue(continuation)
            for await _ in stream { break }
        }
        applied.withValue { $0.append((chapter, mutations)) }
        if let failure = applyFailures.withValue({ $0.isEmpty ? nil : $0.removeFirst() }) {
            throw failure
        }
    }

    /// `holdNextApply()` 가 켜져 있으면 스트림을 만든다.
    private let holdNext = LockIsolated(false)
    func holdNextApply() { holdNext.setValue(true) }
    func releaseApply() {
        applyGate.withValue { $0?.yield(); $0?.finish(); $0 = nil }
    }
    private func makeGateIfNeeded() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation)? {
        guard holdNext.withValue({ let value = $0; $0 = false; return value }) else { return nil }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        return (stream, continuation)
    }
}

enum CanvasTestSupport {
    static let chapter = BibleChapter(title: .jonah, chapter: 2)
    static let layout = OwnershipTestSupport.uniformLayout(verseCount: 3, lineSpace: 30)
    static let otherLayout = OwnershipTestSupport.uniformLayout(verseCount: 3, lineSpace: 40)
    static let rowA = BibleDrawingRowID(raw: "row-a")
    /// `load` 로 1, 합성으로 2 — `compose(_:)` 를 마친 직후의 세대.
    static let composedGeneration = 2

    static func snapshot(verse: Int, rowID: BibleDrawingRowID) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(verse: verse, rowID: rowID, isPresent: true, updateDate: nil,
                             lineData: Data([1]), drawingVersion: 1, metadata: nil)
    }

    static func composed(_ layout: ChapterLayout, tag: String) -> ComposedChapterDrawing {
        ComposedChapterDrawing(
            data: Data("composed-\(tag)-\(Int(layout.totalHeight))".utf8),
            ownership: OwnershipSnapshot(map: [:], layoutSignature: layout.signature),
            activeRowIDs: [1: rowA],
            layoutMismatchVerses: [],
            legacyVerses: [1],
            undecodableVerses: []
        )
    }

    static func metadata() -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: layout.signature)
    }

    static func edit(
        _ tag: String, reason: EditReason = .ink, generation: Int = composedGeneration, dirtyBounds: CGRect? = nil
    ) -> CanvasEditSnapshot {
        CanvasEditSnapshot(drawingData: Data("edit-\(tag)".utf8), dirtyBounds: dirtyBounds, reason: reason, generation: generation)
    }

    static let newRow = BibleDrawingRowID(raw: "new-row")

    static func createResult(_ tag: String) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: layout.signature),
            mutations: [.create(verse: 2, rowID: newRow, data: Data("create-\(tag)".utf8), metadata: metadata())],
            issuedRowIDs: [2: newRow]
        )
    }

    static func replaceResult(_ tag: String, rowID: BibleDrawingRowID) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: layout.signature),
            mutations: [.replace(verse: 2, rowID: rowID, data: Data("replace-\(tag)".utf8), metadata: metadata())],
            issuedRowIDs: [:]
        )
    }

    /// 코덱 스텁: 합성은 태그로 구분되는 Data, 편집은 `results` 큐에서 순서대로 꺼낸다. `composeInputs` 가 있으면 합성 입력을 기록한다.
    static func codec(
        results: LockIsolated<[DrawingEditResult]>,
        composeInputs: LockIsolated<[[VerseDrawingSnapshot]]>? = nil
    ) -> DrawingCodecClient {
        DrawingCodecClient(
            compose: { snapshots, layout, _ in
                composeInputs?.withValue { $0.append(snapshots) }
                return composed(layout, tag: "db")
            },
            mutations: { _, _, _, _ in
                results.withValue { $0.isEmpty ? DrawingEditResult(ownership: .empty(layoutSignature: ""), mutations: [], issuedRowIDs: [:]) : $0.removeFirst() }
            }
        )
    }

    @MainActor
    static func makeStore(
        spy: RepositorySpy,
        results: LockIsolated<[DrawingEditResult]> = LockIsolated([]),
        composeInputs: LockIsolated<[[VerseDrawingSnapshot]]>? = nil
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: ChapterCanvasFeature.State(chapter: chapter)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = codec(results: results, composeInputs: composeInputs)
            $0.drawingRepository = spy
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    /// load + layout 을 마쳐 합성된 상태로 만든다. 세대는 `composedGeneration`.
    @MainActor
    static func compose(_ store: TestStoreOf<ChapterCanvasFeature>) async {
        await store.send(.load(chapter: chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(layout))
    }
}

// MARK: - §6-4 합성 게이트

@Suite("Phase 3 — ChapterCanvasFeature · 합성 게이트")
@MainActor
struct ChapterCanvasComposeTesting {
    @Test("조회와 레이아웃의 도착 순서가 바뀌어도 합성 결과가 같고, 둘 중 하나만 있으면 입력이 막힌다 (§14 6-2 · 10)")
    func composeIsOrderIndependent() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }

        let drawingsFirst = CanvasTestSupport.makeStore(spy: spy)
        await drawingsFirst.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3)) {
            $0.expectedVerseCount = 3
            $0.loadRequestID = UUID(0)
            // 장 진입은 세대를 올린다 — 뷰가 빈 캔버스를 즉시 표시하도록.
            $0.renderedRevision = 1
        }
        await drawingsFirst.receive(\.drawingsLoaded) {
            $0.loadedDrawings = [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)]
        }
        #expect(!drawingsFirst.state.isInputEnabled)
        await drawingsFirst.send(.layoutCompleted(CanvasTestSupport.layout)) {
            $0.layout = CanvasTestSupport.layout
            $0.renderedRevision = 2
            $0.renderedLayout = CanvasTestSupport.layout
            $0.activeRowIDs = [1: CanvasTestSupport.rowA]
            $0.legacyVerses = [1]
        }
        #expect(drawingsFirst.state.isInputEnabled)

        let layoutFirst = CanvasTestSupport.makeStore(spy: spy)
        await layoutFirst.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(!layoutFirst.state.isInputEnabled)
        await layoutFirst.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        // load 는 이전 레이아웃을 버린다 — 새 장의 레이아웃은 다시 와야 한다.
        await layoutFirst.receive(\.drawingsLoaded)
        #expect(!layoutFirst.state.isInputEnabled)
        await layoutFirst.send(.layoutCompleted(CanvasTestSupport.layout))

        #expect(layoutFirst.state.renderedData == drawingsFirst.state.renderedData)
        #expect(layoutFirst.state.baselineData == drawingsFirst.state.renderedData)
        #expect(layoutFirst.state.ownership == drawingsFirst.state.ownership)
    }

    @Test("절 개수가 맞지 않는 레이아웃으로는 합성하지 않는다 (§6-2)")
    func mismatchedVerseCountKeepsGateClosed() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 4))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))   // 3절짜리

        #expect(store.state.renderedData == nil)
        #expect(!store.state.isInputEnabled)
    }

    @Test("이전 장의 조회 결과는 폐기된다 (§14 6-3)")
    func staleLoadIsDiscarded() async {
        let spy = RepositorySpy()
        let second = BibleChapter(title: .jonah, chapter: 3)
        spy.snapshots = { chapter in
            chapter == second ? [CanvasTestSupport.snapshot(verse: 2, rowID: BibleDrawingRowID(raw: "second"))] : []
        }
        let store = CanvasTestSupport.makeStore(spy: spy)

        // 첫 장의 조회를 붙잡아 두고, 그 사이 다음 장으로 넘어간다.
        spy.holdNextLoadCall()
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3)) { $0.loadRequestID = UUID(0) }
        await store.send(.load(chapter: second, expectedVerseCount: 3)) {
            $0.chapter = second
            $0.loadRequestID = UUID(1)
        }
        await store.receive(\.drawingsLoaded) {
            $0.loadedDrawings = [CanvasTestSupport.snapshot(verse: 2, rowID: BibleDrawingRowID(raw: "second"))]
        }

        // 이제야 첫 장의 결과가 도착한다 — 요청 ID 가 다르므로 상태를 건드리지 않는다.
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)

        #expect(store.state.chapter == second)
        #expect(store.state.loadRequestID == UUID(1))
        #expect(store.state.loadedDrawings == [CanvasTestSupport.snapshot(verse: 2, rowID: BibleDrawingRowID(raw: "second"))])
    }

    @Test("조회 실패는 빈 장이 아니라 닫힌 게이트다 — 기존 행 위에 새 행이 생기지 않도록")
    func loadFailureKeepsGateClosed() async {
        let spy = RepositorySpy()
        spy.loadFailures.setValue(["boom"])
        let store = CanvasTestSupport.makeStore(spy: spy)

        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded) {
            $0.loadedDrawings = nil
            $0.loadFailure = DrawingLoadFailure(message: "boom")
        }
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(!store.state.isInputEnabled)
    }

    @Test("장 진입은 세대를 올리고 스크롤 토큰은 장이 바뀌어도 이어진다 — 뷰의 잔존 토큰과 겹치지 않게")
    func loadBumpsGenerationAndScrollTokensAreMonotonic() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)
        #expect(store.state.renderedRevision == CanvasTestSupport.composedGeneration)

        await store.send(.scrollToVerse(3)) {
            $0.scrollRequestToken = 1
            $0.scrollRequest = .init(verse: 3, token: 1)
        }
        let next = BibleChapter(title: .jonah, chapter: 3)
        await store.send(.load(chapter: next, expectedVerseCount: 3)) {
            $0.chapter = next
            $0.renderedData = nil
            $0.renderedRevision = 3
            $0.scrollRequest = nil
        }
        await store.receive(\.drawingsLoaded)
        // 이전 구현은 토큰을 0 부터 다시 세어 첫 요청이 1 — 뷰가 마지막으로 수행한 토큰(1)과 같아 무시됐다.
        await store.send(.scrollToVerse(1)) {
            $0.scrollRequestToken = 2
            $0.scrollRequest = .init(verse: 1, token: 2)
        }
    }
}

// MARK: - §8 편집 → 저장

@Suite("Phase 3 — ChapterCanvasFeature · 편집과 저장")
@MainActor
struct ChapterCanvasEditTesting {
    private var newRow: BibleDrawingRowID { CanvasTestSupport.newRow }
    private func createResult(_ tag: String) -> DrawingEditResult { CanvasTestSupport.createResult(tag) }
    private func replaceResult(_ tag: String, rowID: BibleDrawingRowID) -> DrawingEditResult { CanvasTestSupport.replaceResult(tag, rowID: rowID) }

    @Test("편집은 pencil-up 순서로 하나씩 코덱을 거치고, 신규 행의 rowID 는 즉시 예약된다 (§8-1 · §8-7)")
    func editsAreProcessedSeriallyAndIssuedRowIDIsReserved() async {
        let spy = RepositorySpy()
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
            $0.pendingMutations = [self.newRow: PendingDrawingMutation(revision: 1, chapter: CanvasTestSupport.chapter, mutation: self.createResult("1").mutations[0])]
            $0.saveStatus = .saving(revision: 1)
            $0.inFlightBatch = [self.newRow: 1]
            $0.inFlightMutations = self.createResult("1").mutations
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
        #expect(store.state.isFullyPersisted)
        #expect(spy.applied.value.map(\.chapter) == [CanvasTestSupport.chapter])
        #expect(spy.applied.value.first?.mutations == createResult("1").mutations)
        // 성공한 저장은 DB 내용(loadedDrawings)에 겹쳐진다 — 재조회 없이도 현재 내용의 근거가 되도록.
        #expect(store.state.loadedDrawings?.contains { $0.rowID == newRow && $0.drawingVersion == 3 } == true)
    }

    @Test("저장 중 도착한 최신 편집은 성공 콜백에 지워지지 않고 다음 batch 로 간다 — create 위의 replace 는 create 로 남는다 (§14 6 · 6-1 · 5-7)")
    func newerRevisionSurvivesInFlightSave() async {
        let spy = RepositorySpy()
        let results = LockIsolated([CanvasTestSupport.createResult("1"), CanvasTestSupport.replaceResult("2", rowID: CanvasTestSupport.newRow)])
        let store = CanvasTestSupport.makeStore(spy: spy, results: results)
        await CanvasTestSupport.compose(store)

        spy.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.saveStatus == .saving(revision: 1))

        // 첫 저장이 붙잡힌 동안 두 번째 편집이 들어온다.
        await store.send(.editEnded(CanvasTestSupport.edit("2")))
        await store.receive(\.mutationsPrepared)
        let merged = store.state.pendingMutations[newRow]
        #expect(merged?.revision == 2)
        #expect(merged?.mutation == .create(verse: 2, rowID: newRow, data: Data("replace-2".utf8), metadata: CanvasTestSupport.metadata()))
        #expect(store.state.saveStatus == .saving(revision: 1))

        spy.releaseApply()
        await store.receive(\.saveFinished) {
            // revision 1 로 저장된 항목만 제거되는데, 큐의 항목은 revision 2 라 남는다.
            $0.persistedRevision = 1
            $0.saveStatus = .saving(revision: 2)
            $0.inFlightBatch = [self.newRow: 2]
        }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
            $0.inFlightBatch = [:]
            $0.persistedRevision = 2
        }
        #expect(spy.applied.value.count == 2)
        #expect(spy.applied.value.last?.mutations == [.create(verse: 2, rowID: newRow, data: Data("replace-2".utf8), metadata: CanvasTestSupport.metadata())])
    }

    @Test("coalesce: 미저장 create 를 덮은 clear 위에 replace 가 오면 create 로 남긴다 — replace 는 행이 없으면 실패한다 (§8-6)")
    func coalesceKeepsRowCreatableAcrossClear() {
        let metadata = CanvasTestSupport.metadata()
        let create: VerseDrawingMutation = .create(verse: 2, rowID: newRow, data: Data([1]), metadata: metadata)
        let clear: VerseDrawingMutation = .clear(verse: 2, rowID: newRow)
        let replace: VerseDrawingMutation = .replace(verse: 2, rowID: newRow, data: Data([2]), metadata: metadata)

        let afterClear = ChapterCanvasFeature.coalesce(existing: create, incoming: clear)
        #expect(afterClear == clear)
        // 이전 구현은 여기서 replace 를 남겨 rowNotFound 로 장 전체 저장이 영구 실패했다.
        let afterReplace = ChapterCanvasFeature.coalesce(existing: afterClear, incoming: replace)
        #expect(afterReplace == .create(verse: 2, rowID: newRow, data: Data([2]), metadata: metadata))
        #expect(ChapterCanvasFeature.coalesce(existing: create, incoming: replace) == .create(verse: 2, rowID: newRow, data: Data([2]), metadata: metadata))
        #expect(ChapterCanvasFeature.coalesce(existing: replace, incoming: clear) == clear)
    }

    @Test("저장 실패는 화면을 되돌리지 않고 큐를 보존하며, flush 가 재시도한다 (§8-4 · §14 8)")
    func failureKeepsQueueAndFlushRetries() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("disk")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)

        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished) {
            $0.saveStatus = .failed(revision: 1, retryCount: 1)
            $0.inFlightBatch = [:]
        }
        #expect(store.state.pendingMutations.count == 1)
        #expect(store.state.baselineData == CanvasTestSupport.edit("1").drawingData)   // 화면(기준) 유지
        #expect(!store.state.isFullyPersisted)

        await store.send(.flushPending) {
            $0.saveStatus = .saving(revision: 1)
            $0.inFlightBatch = [self.newRow: 1]
        }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
            $0.inFlightBatch = [:]
            $0.persistedRevision = 1
        }
        #expect(spy.applied.value.count == 2)
    }

    @Test("편집 중 도착한 레이아웃은 pencil-up 뒤에 적용되고, 미저장분을 저장한 뒤 DB 에서 다시 합성한다 (§14 11 · §9-5)")
    func layoutArrivingDuringEditIsDeferredThenReloaded() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)
        let firstRendered = store.state.renderedData

        await store.send(.editBegan) { $0.isEditing = true }
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout)) {
            $0.pendingLayout = CanvasTestSupport.otherLayout
        }
        #expect(store.state.layout == CanvasTestSupport.layout)
        #expect(store.state.isInputEnabled)

        await store.send(.editEnded(CanvasTestSupport.edit("1"))) {
            $0.isEditing = false
            $0.pendingLayout = nil
            $0.layout = CanvasTestSupport.otherLayout
            $0.reloadWhenSettled = true
            $0.isReloading = true
        }
        #expect(!store.state.isInputEnabled)
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        // 저장이 끝나자 다시 읽고 새 레이아웃으로 합성한다.
        await store.receive(\.drawingsLoaded) {
            $0.renderedRevision = 3
            $0.renderedLayout = CanvasTestSupport.otherLayout
            $0.isReloading = false
            $0.reloadWhenSettled = false
        }
        #expect(store.state.renderedData != firstRendered)
        #expect(store.state.renderedData == CanvasTestSupport.composed(CanvasTestSupport.otherLayout, tag: "db").data)
        #expect(store.state.isInputEnabled)
        #expect(spy.loadedChapters.value.count == 2)
    }

    @Test("편집 중 도착한 columnOrigin 도 pencil-up 뒤에 적용된다 — 획 도중 재합성하면 그 획이 사라진다")
    func columnOriginArrivingDuringEditIsDeferred() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)
        let origin = CGPoint(x: 366.7, y: 0)

        await store.send(.editBegan) { $0.isEditing = true }
        await store.send(.columnOriginChanged(origin)) {
            $0.pendingColumnOrigin = origin
        }
        #expect(store.state.columnOrigin == .zero)
        #expect(store.state.isInputEnabled)
        #expect(!store.state.isReloading)

        await store.send(.editEnded(CanvasTestSupport.edit("1"))) {
            $0.isEditing = false
            $0.pendingColumnOrigin = nil
            $0.columnOrigin = origin
            $0.reloadWhenSettled = true
            $0.isReloading = true
        }
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        await store.receive(\.drawingsLoaded) {
            $0.renderedRevision = 3
            $0.renderedColumnOrigin = origin
            $0.isReloading = false
        }
        #expect(store.state.isInputEnabled)
    }

    @Test("히스토리 복원은 mutation 없이 다시 합성하고, 미저장분이 있으면 먼저 저장한다 (§14 5-2 · 5-3)")
    func restoreReloadsWithoutMutationsAfterSettling() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)

        spy.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)

        await store.send(.verseRowRestored(verse: 2, rowID: BibleDrawingRowID(raw: "older"))) {
            $0.reloadWhenSettled = true
            $0.isReloading = true
        }
        #expect(spy.loadedChapters.value.count == 1)   // 아직 다시 읽지 않았다

        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(\.drawingsLoaded) {
            $0.renderedRevision = 3
            $0.isReloading = false
        }
        #expect(spy.loadedChapters.value.count == 2)
        #expect(spy.applied.value.count == 1)          // 복원 자체는 저장을 만들지 않았다
        #expect(store.state.isFullyPersisted)
    }

    @Test("장을 바꾸면 이전 장의 실패한 batch 를 곧바로 다시 시도하고, 자기 장으로 저장한다 (§8-5 · §14 7)")
    func pendingMutationsOfPreviousChapterAreSavedToThatChapter() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("offline")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)

        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)   // 실패 → 큐 보존
        #expect(store.state.pendingMutations.count == 1)

        let next = BibleChapter(title: .jonah, chapter: 3)
        spy.holdNextLoadCall()
        await store.send(.load(chapter: next, expectedVerseCount: 3)) {
            $0.chapter = next
            $0.renderedData = nil
            // 장 전환은 flush 지점이다 — 이전 장의 batch 가 곧바로 다시 나간다.
            $0.saveStatus = .saving(revision: 1)
            $0.inFlightBatch = [self.newRow: 1]
        }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
            $0.inFlightBatch = [:]
        }
        #expect(spy.applied.value.last?.chapter == CanvasTestSupport.chapter)
        // 새 장의 DB 내용(loadedDrawings)은 이전 장 batch 로 오염되지 않는다.
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded) { $0.loadedDrawings = [] }
    }
}

// MARK: - rev.17 편집 세대와 재합성 게이트 출구

@Suite("Phase 3 — ChapterCanvasFeature · 편집 세대와 재합성 출구 (rev.17)")
@MainActor
struct ChapterCanvasGenerationTesting {
    private var newRow: BibleDrawingRowID { CanvasTestSupport.newRow }

    @Test("장 전환 뒤 도착한 이전 장의 editEnded 는 물러난 세션에서 계산돼 이전 장으로 저장된다 — 새 장 기준으로 처리하지 않는다")
    func lateEditOfPreviousChapterIsSavedToPreviousChapter() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("late")]))
        await CanvasTestSupport.compose(store)
        let previousGeneration = store.state.renderedRevision

        let next = BibleChapter(title: .jonah, chapter: 3)
        spy.holdNextLoadCall()
        await store.send(.load(chapter: next, expectedVerseCount: 3)) {
            $0.chapter = next
            $0.renderedRevision = previousGeneration + 1
        }
        #expect(store.state.retiredSession?.generation == previousGeneration)
        #expect(store.state.retiredSession?.chapter == CanvasTestSupport.chapter)

        // 장 전환 직전의 마지막 획 — 컨트롤러가 이전 세대 번호로 늦게 보고한다.
        await store.send(.editEnded(CanvasTestSupport.edit("late", generation: previousGeneration))) {
            $0.editRevision = 1
            $0.editQueue = [.init(revision: 1, snapshot: CanvasTestSupport.edit("late", generation: previousGeneration))]
            $0.isPreparingEdit = true
        }
        await store.receive(\.mutationsPrepared) {
            $0.isPreparingEdit = false
            $0.editQueue = []
            $0.pendingMutations = [self.newRow: PendingDrawingMutation(
                revision: 1, chapter: CanvasTestSupport.chapter, mutation: CanvasTestSupport.createResult("late").mutations[0]
            )]
            $0.saveStatus = .saving(revision: 1)
        }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
        }
        #expect(spy.applied.value.last?.chapter == CanvasTestSupport.chapter)
        // 새 장의 문맥은 손대지 않았다 — 기준·소유권·활성 행이 비어 있고 입력은 여전히 닫혀 있다.
        #expect(store.state.baselineData == nil)
        #expect(store.state.activeRowIDs.isEmpty)
        #expect(store.state.chapter == next)
        #expect(!store.state.isInputEnabled)

        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(store.state.isInputEnabled)
    }

    @Test("어느 세대에도 속하지 않는 editEnded 는 버린다 — 큐가 막히거나 다른 내용 기준으로 저장되지 않게")
    func editOfUnknownGenerationIsDropped() async {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("x")]))
        await CanvasTestSupport.compose(store)

        await store.send(.editBegan) { $0.isEditing = true }
        await store.send(.editEnded(CanvasTestSupport.edit("x", generation: 99))) {
            $0.isEditing = false
        }
        #expect(store.state.editQueue.isEmpty)
        #expect(store.state.editRevision == 0)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.isInputEnabled)
    }

    @Test("재합성이 저장 완료를 기다리는데 저장이 실패하면, DB 내용 ⊕ 미저장분으로 합성해 입력을 다시 열고 재조회는 저장 성공 뒤로 미룬다")
    func saveFailureWhileReloadPendingReopensInput() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("disk"), .persistenceFailed("disk")])
        let composeInputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = CanvasTestSupport.makeStore(
            spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]), composeInputs: composeInputs
        )
        await CanvasTestSupport.compose(store)

        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished) { $0.saveStatus = .failed(revision: 1, retryCount: 1) }

        // 레이아웃이 바뀌어 재합성이 필요하다 — 미저장분부터 다시 저장하려 하지만 또 실패한다.
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout)) {
            $0.layout = CanvasTestSupport.otherLayout
            $0.reloadWhenSettled = true
            $0.isReloading = true
            $0.saveStatus = .saving(revision: 1)
        }
        #expect(!store.state.isInputEnabled)
        await store.receive(\.saveFinished) {
            // retryCount 는 `.saving` 을 거치며 1 로 돌아온다 (기존 동작 — 재시도 횟수는 로그용이다).
            $0.saveStatus = .failed(revision: 1, retryCount: 1)
            // 이전 구현은 여기서 isReloading 이 영원히 true — 입력이 잠긴 채 재시도할 편집도 생기지 않았다.
            $0.isReloading = false
            $0.renderedRevision = 3
            $0.renderedLayout = CanvasTestSupport.otherLayout
            $0.reloadWhenSettled = true
        }
        #expect(store.state.isInputEnabled)
        #expect(store.state.pendingMutations.count == 1)
        #expect(store.state.renderedData == CanvasTestSupport.composed(CanvasTestSupport.otherLayout, tag: "db").data)
        // 합성 입력에 미저장 create 행이 겹쳐져 있다 — 실패한 잉크가 화면에서 사라지지 않는다.
        let lastInput = composeInputs.value.last ?? []
        #expect(lastInput.contains { $0.rowID == newRow && $0.drawingVersion == 3 && $0.lineData == Data("create-1".utf8) })
        #expect(spy.loadedChapters.value.count == 1)

        // 저장이 성공하면 미뤄 둔 DB 재조회가 이어진다.
        await store.send(.flushPending) { $0.saveStatus = .saving(revision: 1) }
        await store.receive(\.saveFinished) {
            $0.pendingMutations = [:]
            $0.saveStatus = .idle
            $0.reloadWhenSettled = false
            $0.isReloading = true
        }
        await store.receive(\.drawingsLoaded) {
            $0.renderedRevision = 4
            $0.isReloading = false
        }
        #expect(spy.loadedChapters.value.count == 2)
        #expect(store.state.isInputEnabled)
    }

    @Test("재조회가 실패하면 마지막으로 알고 있는 DB 내용으로 합성해 입력을 다시 연다")
    func reloadFailureReopensInputFromLastKnownContent() async {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        let composeInputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = CanvasTestSupport.makeStore(spy: spy, composeInputs: composeInputs)
        await CanvasTestSupport.compose(store)

        spy.loadFailures.setValue(["boom"])
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout)) {
            $0.layout = CanvasTestSupport.otherLayout
            $0.isReloading = true
            $0.reloadWhenSettled = false
        }
        await store.receive(\.drawingsLoaded) {
            $0.loadFailure = DrawingLoadFailure(message: "boom")
            $0.isReloading = false
            $0.renderedRevision = 3
            $0.renderedLayout = CanvasTestSupport.otherLayout
        }
        #expect(store.state.isInputEnabled)
        #expect(store.state.loadedDrawings == [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)])
        #expect(composeInputs.value.last == [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)])
    }

    @Test("저장이 실패한 채 장을 떠났다 돌아오면 미저장분이 합성 입력에 겹쳐진다 — 잉크가 화면에서 사라지지 않고 재시도도 이어진다")
    func unsavedMutationsAreOverlaidWhenRevisitingChapter() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("1"), .persistenceFailed("2"), .persistenceFailed("3")])
        let composeInputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = CanvasTestSupport.makeStore(
            spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]), composeInputs: composeInputs
        )
        await CanvasTestSupport.compose(store)
        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)   // 실패 1

        let other = BibleChapter(title: .jonah, chapter: 3)
        spy.holdNextLoadCall()
        await store.send(.load(chapter: other, expectedVerseCount: 3))
        await store.receive(\.saveFinished)   // 장 전환 flush — 실패 2
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)

        spy.holdNextLoadCall()
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.saveFinished)   // 실패 3
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))

        #expect(store.state.isInputEnabled)
        #expect(store.state.pendingMutations.count == 1)
        let lastInput = composeInputs.value.last ?? []
        #expect(lastInput.contains { $0.rowID == newRow && $0.lineData == Data("create-1".utf8) })
    }
}
