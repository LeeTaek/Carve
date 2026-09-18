//
//  ChapterCanvasEditSessionTesting.swift
//  CarveFeatureTest
//
//  편집 세션의 계정 · K 근거 — 바뀌면 미저장분을 닫는 세션의 초안으로 남기고 유효한 내용으로 다시 연다 (정책 §12-6 구현 순서 ① · ②).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 테스트가 바꿀 수 있는 편집 환경. 바꾸면 구독자에게 알린다.
final class ControlledEditEnvironment: DrawingEditEnvironmentClient, @unchecked Sendable {
    let environment: LockIsolated<DrawingEditEnvironment>
    private let continuations = LockIsolated<[AsyncStream<Void>.Continuation]>([])

    init(_ initial: DrawingEditEnvironment) {
        environment = LockIsolated(initial)
    }

    var subscriberCount: Int { continuations.value.count }

    func current() async -> DrawingEditEnvironment { environment.value }
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool { environment.value.serverWork == token }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuations.withValue { $0.append(continuation) }
        return stream
    }

    func change(to next: DrawingEditEnvironment) {
        environment.setValue(next)
        continuations.value.forEach { $0.yield() }
    }

    func finish() {
        continuations.value.forEach { $0.finish() }
    }
}

/// 초안 저장 대역 — 실제 저장소(`LocalPreservationWriter`)처럼 더 새 revision 을 지키고, 이어받은 다른 세션의 초안을 지운다.
/// `failures` 만큼 먼저 실패하고(공간 부족 등), `rejectNext` 면 전체 삭제 세대로 거절하며, `holdNextSave()` 면 `release()` 까지 붙잡는다.
/// `readFailures` 만큼 장 단위 읽기를 실패한다(삭제 세대를 읽지 못함 등).
final class RecordingDraftStore: VerseDraftStore, @unchecked Sendable {
    struct Full: Error {}
    struct Unreadable: Error {}

    private struct Entry: Equatable {
        let scope: AccountScope
        let draft: VerseDraft
    }

    private let entries = LockIsolated<[String: Entry]>([:])
    /// 받아들인 저장 요청(실패 · 거절 제외).
    let saves = LockIsolated<[VerseDraft]>([])
    /// 지운 초안 — 이어받아 지운 것과 저장을 마쳐 지운 것.
    let removed = LockIsolated<[VerseDraftKey]>([])
    let failures = LockIsolated(0)
    let readFailures = LockIsolated(0)
    let rejectNext = LockIsolated(false)
    private let holdNext = LockIsolated(false)
    private let gate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)

    /// 다음 저장을 `release()` 까지 붙잡는다 — 초안을 쓰는 동안의 상태를 보기 위함.
    func holdNextSave() { holdNext.setValue(true) }
    func release() { gate.withValue { $0?.yield(); $0?.finish(); $0 = nil } }

    /// 시험 준비 — 앞선 세션이 남긴 초안을 넣는다.
    func seed(_ draft: VerseDraft) {
        let scope = draft.account.preservationScope
        entries.withValue { $0[Self.id(scope, draft.key)] = Entry(scope: scope, draft: draft) }
    }

    /// 그 묶음에 지금 남아 있는 초안.
    func stored(in scope: AccountScope) -> [VerseDraft] {
        entries.value.values.filter { $0.scope == scope }.map(\.draft)
            .sorted { ($0.key.verse, $0.key.sessionID) < ($1.key.verse, $1.key.sessionID) }
    }

    func saveDraft(_ draft: VerseDraft, superseding: [VerseDraftRef]) async throws -> LocalPreservationWriter.WriteOutcome {
        if holdNext.withValue({ value -> Bool in defer { value = false }; return value }) {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            gate.setValue(continuation)
            for await _ in stream { break }
        }
        if rejectNext.withValue({ value -> Bool in defer { value = false }; return value }) {
            return .rejectedByErase(current: 1)
        }
        let shouldFail = failures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw Full() }
        saves.withValue { $0.append(draft) }
        let scope = draft.account.preservationScope
        let removedKeys = entries.withValue { entries -> [VerseDraftKey] in
            let id = Self.id(scope, draft.key)
            if let existing = entries[id], existing.draft.revision > draft.revision { return [] }
            entries[id] = Entry(scope: scope, draft: draft)
            return superseding.filter { ref in
                // 그 revision 일 때만 대신한다 — 더 새 revision 이 쓰였으면 남긴다.
                let oldID = Self.id(scope, ref.key)
                guard ref.key.sessionID != draft.key.sessionID, entries[oldID]?.draft.revision == ref.revision else { return false }
                entries[oldID] = nil
                return true
            }.map(\.key)
        }
        removed.withValue { $0.append(contentsOf: removedKeys) }
        return .written
    }

    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] {
        let shouldFail = readFailures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw Unreadable() }
        return stored(in: scope).filter {
            $0.key.title == chapter.title.rawValue && $0.key.chapter == chapter.chapter && $0.key.translation == translation.rawValue
        }
    }

    /// 이만큼 "들어감" 표식 쓰기를 실패한다 — 저장소 저장 뒤 표식을 남기기 전에 끝난 것과 같다.
    let markFailures = LockIsolated(0)

    func markDraftStored(_ key: VerseDraftKey, scope: AccountScope, throughRevision revision: Int) async throws {
        let shouldFail = markFailures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw Full() }
        entries.withValue { entries in
            let id = Self.id(scope, key)
            guard let entry = entries[id], entry.draft.revision <= revision else { return }
            var draft = entry.draft
            draft.storeState = .stored
            entries[id] = Entry(scope: scope, draft: draft)
        }
    }

    /// 로컬 삭제 세대 — 시험 환경의 기본값(0)과 같다.
    let generation = LockIsolated<UInt64?>(0)
    func currentGeneration() async -> UInt64? { generation.value }

    func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) async throws {
        let didRemove = entries.withValue { entries -> Bool in
            let id = Self.id(scope, key)
            guard entries[id]?.draft.revision == revision else { return false }
            entries[id] = nil
            return true
        }
        if didRemove { removed.withValue { $0.append(key) } }
    }

    private static func id(_ scope: AccountScope, _ key: VerseDraftKey) -> String {
        [scope.key, key.sessionID, key.translation, key.title, "\(key.chapter)", "\(key.verse)"].joined(separator: "|")
    }
}

/// 편집 세션 시험들이 함께 쓰는 준비 — 환경 · 초안 대역과 저장소, 합성 · 편집 붙잡기.
@MainActor
protocol EditSessionTestHelpers {}

extension EditSessionTestHelpers {
    var accountA: AccountScope { AccountScope(key: "acct-a") }
    var accountB: AccountScope { AccountScope(key: "acct-b") }

    /// 확인된 계정 환경. 기본은 저장소 소유 근거가 그 계정인 경우다 — 근거가 없는 경우는 `owned: false` 로 따로 본다.
    func confirmed(
        _ scope: AccountScope,
        _ generation: UInt64,
        knowledge: EraseEpochKnowledge? = EraseEpochKnowledge(),
        owned: Bool = true
    ) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope),
            serverWork: AccountServerWorkToken(scope: scope, generation: generation),
            knowledge: knowledge,
            storeOwnership: owned ? scope : nil
        )
    }

    func makeStore(
        spy: RepositorySpy,
        results: [DrawingEditResult],
        environment: ControlledEditEnvironment,
        drafts: RecordingDraftStore?,
        clock: any Clock<Duration> = ImmediateClock(),
        composeInputs: LockIsolated<[[VerseDrawingSnapshot]]>? = nil
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results), composeInputs: composeInputs)
            $0.drawingRepository = spy
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
            $0.drawingEditEnvironment = environment
            $0.verseDraftStore = drafts
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    /// 합성하고, 환경 구독이 걸릴 때까지 기다린다.
    func composeAndSubscribe(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment) async {
        await CanvasTestSupport.compose(store)
        while environment.subscriberCount == 0 { await Task.yield() }
    }

    /// 저장소 저장이 붙잡힌 채(진행 중) 편집 하나를 미저장분으로 만든다.
    func holdOneEdit(_ store: TestStoreOf<ChapterCanvasFeature>, _ spy: RepositorySpy, tag: String = "a") async {
        spy.holdNextApply()
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit(tag)))
        await store.receive(\.mutationsPrepared)
    }

    /// 초안 저장을 붙잡은 채 편집 하나를 만든다 — 초안이 되기 전의 미저장분.
    func editWithHeldDraft(_ store: TestStoreOf<ChapterCanvasFeature>, _ drafts: RecordingDraftStore, tag: String = "a") async {
        drafts.holdNextSave()
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit(tag)))
        await store.receive(\.mutationsPrepared)
    }

    /// 화면에 캔버스가 있다 — 세션을 닫을 때 인계 응답을 기다린다. 뷰처럼 지금 세대를 표시했다고도 알린다.
    func attachCanvas(_ store: TestStoreOf<ChapterCanvasFeature>, id: UUID = UUID(700)) async {
        await store.send(.canvasAttached(id: id))
        await store.send(.canvasDisplayed(id: id, revision: store.state.renderedRevision))
    }

    func end(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment) async {
        environment.finish()
        await store.finish()
    }
}

/// 이 파일이 막는 것:
/// - 계정이 바뀐 뒤에 이전 세션의 편집을 새 계정 저장소에 저장하는 것(계정 혼합)
/// - 계정 · 기준점이 바뀌었다고 미저장분을 버리는 것(조용한 유실) — 닫는 세션의 초안으로 남긴 **뒤에만** 화면을 정리한다
/// - 같은 계정의 재확인 · 확인 중에 편집을 끊는 것
@Suite("편집 세션 — 계정 · 기준점이 바뀌면 초안으로 남기고 다시 연다")
@MainActor
struct ChapterCanvasEditSessionTesting: EditSessionTestHelpers {
    // MARK: - 계정이 바뀜

    @Test("계정이 바뀌면 입력 · 저장을 막고, 미저장분을 닫는 세션(계정 A)의 초안으로 남긴 뒤에만 새 환경으로 다시 연다")
    func accountChangePreservesDraftThenReloads() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        // 캔버스가 없으면 인계를 기다리지 않고 곧바로 닫는다. 다시 읽기가 끝날 때까지 새 획을 받지 않는다 — 바뀐 근거 아래서 새 편집이
        // 시작되지 않는다.
        #expect(store.state.sessionEnd == nil)
        #expect(!store.state.isInputEnabled)

        // 초안은 무효가 된 세션(계정 A)의 묶음에 그 세션의 근거를 들고 남았다. 새 계정 묶음에는 없다.
        let preserved = drafts.stored(in: accountA)
        #expect(preserved.map(\.key.verse) == [2])
        #expect(preserved.first?.lineData == Data("create-a".utf8))
        #expect(preserved.first?.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(drafts.stored(in: accountB).isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))

        // 진행 중이던 저장이 끝나면 다시 읽는다. 바뀐 계정 아래로는 한 번도 저장하지 않았다.
        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    /// 기준점을 알게 된 것도 같은 흐름이다 — 편집 중이던 내용은 그 삭제를 모른 채 쓴 것이다.
    @Test("모르던 삭제 기준점을 알게 되면 미저장분을 그 기준점을 모르는 K 의 초안으로 남긴다")
    func learnedErasePreservesDraftWithOldKnowledge() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)
        var learned = EraseEpochKnowledge()
        learned.receive("E1")

        environment.change(to: confirmed(accountA, 1, knowledge: learned))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd == nil)

        #expect(drafts.stored(in: accountA).first?.knownEpochs == [])
        #expect(store.state.editEnvironment.knowledge?.all == ["E1"])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    // MARK: - 늦게 온 편집

    /// 캔버스가 있으면 응답이 늦어도 닫지 않는다 — 그 사이 도착한 늦은 편집은 무효가 된 세션의 것이므로 그 세션의 초안에 넣는다.
    @Test("인계를 기다리는 동안 늦게 온 편집도 닫는 세션의 초안에 넣고, 저장소에는 쓰지 않는다 — 시한이 지나도 닫지 않고 다시 요청한다")
    func lateEditJoinsClosingSessionDraft() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("b")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        // 멎기를 기다리는 사이 늦은 편집이 온다. 닫는 세션(계정 A)의 초안이 된다.
        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await clock.advance(by: ChapterCanvasFeature.sessionHandoffTimeout)
        await store.receive(\.sessionHandoffTimedOut)
        // 캔버스가 있다 — 응답이 늦을 뿐이다. 닫지 않고 새 토큰으로 다시 요청한다.
        let token = store.state.handoffToken
        #expect(store.state.sessionEnd?.phase == .handingOff(token: token))
        await store.send(.editHandoffCompleted(token: token))
        #expect(store.state.sessionEnd == nil)

        // 같은 절의 완전한 획 집합이므로 최신(b)이 계정 A 의 초안으로 남는다.
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-b".utf8)])
        #expect(drafts.stored(in: accountB).isEmpty)
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        // 늦은 편집(b)은 저장소에 쓰지 않았다 — 붙잡혀 있던 a 한 번뿐이다.
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    /// 뷰가 디바운스 안의 마지막 획을 보고하고 인계를 마치면, 시한을 기다리지 않고 그 획까지 초안에 넣은 뒤 닫는다.
    @Test("뷰가 인계를 마치면 시한을 기다리지 않고, 인계로 받은 마지막 획까지 닫는 세션의 초안에 넣고 닫는다")
    func viewHandoffClosesWithoutWaiting() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("b")],
            environment: environment, drafts: drafts, clock: clock
        )
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let token = store.state.handoffToken
        #expect(store.state.sessionEnd?.phase == .handingOff(token: token))

        // 앞서 요청한 인계의 늦은 응답은 받지 않는다.
        await store.send(.editHandoffCompleted(token: token - 1))
        #expect(store.state.sessionEnd?.phase == .handingOff(token: token))

        // 뷰가 마지막 획(b)을 보고하고 인계를 마친다. 그 획은 닫는 세션(계정 A)의 초안이 된다.
        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        #expect(store.state.sessionEnd != nil)
        await store.send(.editHandoffCompleted(token: token))

        // 시계를 움직이지 않았다 — 시한이 아니라 인계로 닫혔다.
        #expect(store.state.sessionEnd == nil)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-b".utf8)])
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    /// 인계가 끝났어도 편집 구간이 열려 있으면(획의 취소 알림 전) 닫지 않고, 구간이 닫힐 때 이어 닫는다.
    @Test("인계를 마친 뒤에도 편집 구간이 열려 있으면 기다렸다가, 닫히면 곧바로 이어 닫는다")
    func handoffWaitsForOpenEditSpan() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let clock = TestClock()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts, clock: clock)
        await composeAndSubscribe(store, environment)
        await attachCanvas(store)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        let token = store.state.handoffToken
        await store.send(.editBegan)
        await store.send(.editHandoffCompleted(token: token))
        #expect(store.state.sessionEnd?.phase == .draining)

        await store.send(.editCancelled)
        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    @Test("비활성화(저장 요청)는 뷰에도 인계를 요청해 디바운스 안의 마지막 획까지 보고받는다")
    func flushRequestsHandoff() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: RecordingDraftStore())
        await composeAndSubscribe(store, environment)
        let before = store.state.handoffToken

        await store.send(.flushPending)

        #expect(store.state.handoffToken == before + 1)
        #expect(store.state.sessionEnd == nil)
        await end(store, environment)
    }

    // MARK: - 초안 실패

    /// 공간이 부족해 초안을 남기지 못했으면, 미저장분을 버리지도 바뀐 계정에 저장하지도 않는다.
    @Test("초안으로 남기지 못하면 입력 · 저장을 막은 채 다시 시도를 기다리고, 성공한 뒤에만 다시 연다")
    func draftFailureKeepsEverythingBlocked() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        // 초안이 아직 끝나지 않은 미저장분 — 저장소 저장은 초안이 남은 뒤에만 시작하므로 아직 시작하지도 않았다.
        drafts.holdNextSave()
        await holdOneEdit(store, spy)
        #expect(spy.appliedGenerations.value.isEmpty)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd?.phase == .preserving)
        // 쓰던 초안이 공간 부족으로 실패한다.
        drafts.failures.setValue(1)
        drafts.release()
        await store.receive(\.draftsSaved)
        guard case .failed = store.state.sessionEnd?.phase else {
            Issue.record("초안 실패가 남지 않았다: \(String(describing: store.state.sessionEnd))")
            return
        }
        #expect(!store.state.pendingMutations.isEmpty)
        #expect(!store.state.isInputEnabled)

        // 「다시 시도」 — 저장이 아니라 초안을 다시 남긴다. 입력은 닫기 시작할 때부터 막혀 있어 인계를 다시 하지 않는다.
        await store.send(.flushPending)
        await store.receive(\.draftsSaved)
        #expect(store.state.sessionEnd == nil)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-a".utf8)])

        await store.receive(\.drawingsLoaded)
        #expect(store.state.saveStatus == .idle)
        #expect(store.state.isInputEnabled)
        // 초안이 되지 않은 편집은 저장소에 가지 않았고, 바뀐 계정 아래로도 저장하지 않았다.
        #expect(spy.appliedGenerations.value.isEmpty)
        spy.releaseApply()
        await end(store, environment)
    }

    // MARK: - 끊지 않는 경우

    /// 계정 변경 알림은 같은 계정에서도 온다.
    @Test("같은 계정으로 다시 확인되면 세션을 이어 가고 새 표를 들며, 저장을 마친 초안도 지우지 않는다")
    func sameAccountReconfirmationContinues() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        await store.receive(\.draftsSaved)

        environment.change(to: confirmed(accountA, 2))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountA, 2))
        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.pendingMutations.isEmpty)
        await end(store, environment)
        // 저장소 저장은 로컬 확정일 뿐이다 — 전송 전에 계정이 바뀌면 그 행은 지워진다(ACC-1 F29). 초안은 ③ 의 확정이 정리한다.
        #expect(drafts.stored(in: accountA).count == 1)
        #expect(drafts.removed.value.isEmpty)
    }

    @Test("계정을 확인하는 중에는 세션을 끝내지 않고 근거도 바꾸지 않으며, 저장소 저장을 멈춘다")
    func unconfirmedWhileCheckingKeepsSession() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        // 초안이 남은 뒤에 저장소 저장이 시작된다(붙잡힘).
        await store.receive(\.draftsSaved)

        environment.change(to: DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                      knowledge: EraseEpochKnowledge()))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        #expect(store.state.sessionValidity == .awaitingAccountConfirmation)
        #expect(!store.state.persistsToStore)
        spy.releaseApply()
        await store.receive(\.saveFinished)
        await end(store, environment)
    }

    @Test("지킬 미저장분이 없으면 초안 없이 새 환경으로 다시 연다")
    func nothingToProtectJustReloads() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        let loadsBefore = spy.loadedChapters.value.count

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(drafts.saves.value.isEmpty)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(spy.loadedChapters.value.count == loadsBefore + 1)
        #expect(store.state.isInputEnabled)
        await end(store, environment)
    }

    // MARK: - 사용자 전체 삭제

    /// 사용자가 요청한 전체 삭제는 미저장분을 버린다 — 닫던 세션의 것도 초안으로 남기지 않는다(초안 영역도 함께 지워진다).
    @Test("세션을 닫는 중에 전체 삭제가 오면 초안으로 남기지 않고 정리한다")
    func eraseAllDuringSessionEndSkipsPreservation() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        drafts.holdNextSave()
        await holdOneEdit(store, spy)
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd?.phase == .preserving)

        await store.send(.drawingDataCleared)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        // 전체 삭제가 로컬 삭제 세대를 올렸으므로, 붙잡혀 있던 초안은 실제 저장소에서 거절된다. 그 늦은 응답은 버린다.
        drafts.rejectNext.setValue(true)
        drafts.release()
        await store.receive(\.draftsSaved)
        #expect(drafts.saves.value.isEmpty)
        #expect(store.state.sessionEnd == nil)
        spy.releaseApply()
        await end(store, environment)
    }
}
