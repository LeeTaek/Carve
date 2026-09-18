//
//  ChapterCanvasEditSessionTesting.swift
//  CarveFeatureTest
//
//  편집 세션의 계정 · K 근거 — 바뀌면 미저장분을 격리하고 유효한 내용으로 다시 연다 (정책 §12-6 구현 순서 ①).
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

/// 격리 요청을 기록한다. `failures` 만큼 먼저 실패한다(공간 부족 등).
final class RecordingQuarantine: DrawingQuarantineClient, @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let items: [DrawingQuarantineItem]
        let environment: DrawingEditEnvironment
    }

    struct Full: Error {}

    let calls = LockIsolated<[Call]>([])
    let failures = LockIsolated(0)

    func quarantine(_ items: [DrawingQuarantineItem], environment: DrawingEditEnvironment) async throws {
        let shouldFail = failures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw Full() }
        calls.withValue { $0.append(Call(items: items, environment: environment)) }
    }
}

/// 이 파일이 막는 것:
/// - 계정이 바뀐 뒤에 이전 세션의 편집을 새 계정 저장소에 저장하는 것(계정 혼합)
/// - 계정 · 기준점이 바뀌었다고 미저장분을 버리는 것(조용한 유실) — 격리한 **뒤에만** 화면을 정리한다
/// - 같은 계정의 재확인 · 확인 중에 편집을 끊는 것
@Suite("편집 세션 — 계정 · 기준점이 바뀌면 격리 후 다시 연다")
@MainActor
struct ChapterCanvasEditSessionTesting {
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")

    private func confirmed(_ scope: AccountScope, _ generation: UInt64, knowledge: EraseEpochKnowledge = EraseEpochKnowledge()) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope),
            serverWork: AccountServerWorkToken(scope: scope, generation: generation),
            knowledge: knowledge
        )
    }

    private func makeStore(
        spy: RepositorySpy,
        results: [DrawingEditResult],
        environment: ControlledEditEnvironment,
        quarantine: RecordingQuarantine
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = TestStore(initialState: ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated(results))
            $0.drawingRepository = spy
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
            $0.drawingEditEnvironment = environment
            $0.drawingQuarantine = quarantine
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    /// 합성하고, 환경 구독이 걸릴 때까지 기다린다.
    private func composeAndSubscribe(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment) async {
        await CanvasTestSupport.compose(store)
        while environment.subscriberCount == 0 { await Task.yield() }
    }

    /// 저장이 붙잡힌 채(진행 중) 편집 하나를 미저장분으로 만든다.
    private func holdOneEdit(_ store: TestStoreOf<ChapterCanvasFeature>, _ spy: RepositorySpy, tag: String = "a") async {
        spy.holdNextApply()
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit(tag)))
        await store.receive(\.mutationsPrepared)
    }

    private func end(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment) async {
        environment.finish()
        await store.finish()
    }

    // MARK: - 계정이 바뀜

    @Test("계정이 바뀌면 입력 · 저장을 막고 미저장분을 격리한 뒤에만 새 환경으로 다시 연다")
    func accountChangeQuarantinesThenReloads() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        await holdOneEdit(store, spy)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        // 닫는 동안은 새 획을 받지 않는다 — 바뀐 근거 아래서 새 편집이 시작되지 않는다.
        #expect(!store.state.isInputEnabled)
        #expect(store.state.sessionEnd?.environment == confirmed(accountA, 1))
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)

        // 격리본은 무효가 된 세션(계정 A)의 근거를 든다.
        let calls = quarantine.calls.value
        #expect(calls.count == 1)
        #expect(calls.first?.environment == confirmed(accountA, 1))
        #expect(calls.first?.items.map(\.verse) == [2])
        #expect(calls.first?.items.first?.lineData == Data("create-a".utf8))
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
    @Test("모르던 삭제 기준점을 알게 되면 미저장분을 그 기준점을 모르는 K 로 격리한다")
    func learnedEraseQuarantines() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        var learned = EraseEpochKnowledge()
        learned.receive("E1")

        environment.change(to: confirmed(accountA, 1, knowledge: learned))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.sessionEnd?.reason == .eraseLearned)
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)

        #expect(quarantine.calls.value.first?.environment.knowledge.all == [])
        #expect(store.state.editEnvironment.knowledge.all == ["E1"])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        await end(store, environment)
    }

    // MARK: - 늦게 온 편집

    /// 입력을 막아도 뷰는 막기 직전의 획을 0.3초 뒤에 보고한다. 그 편집도 무효가 된 세션의 것이므로 격리에 넣어야 한다.
    @Test("세션을 닫기 시작한 뒤 늦게 온 편집도 격리에 넣고, 저장하지 않는다")
    func lateEditIsQuarantinedToo() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let clock = TestClock()
        let store = TestStore(initialState: ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)) {
            ChapterCanvasFeature()
        } withDependencies: {
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([CanvasTestSupport.createResult("a"), CanvasTestSupport.createResult("b")]))
            $0.drawingRepository = spy
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
            $0.drawingEditEnvironment = environment
            $0.drawingQuarantine = quarantine
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        // 멎기를 기다리는 사이 늦은 편집이 온다.
        await store.send(.editEnded(CanvasTestSupport.edit("b")))
        await store.receive(\.mutationsPrepared)
        await clock.advance(by: ChapterCanvasFeature.sessionSettleDelay)
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)

        // 같은 절의 완전한 획 집합이므로 최신(b)이 격리된다.
        #expect(quarantine.calls.value.first?.items.map(\.lineData) == [Data("create-b".utf8)])
        spy.releaseApply()
        await store.receive(\.drawingsLoaded)
        // 늦은 편집(b)은 저장하지 않았다 — 붙잡혀 있던 a 한 번뿐이다.
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    // MARK: - 격리 실패

    /// 공간이 부족해 격리하지 못했으면, 미저장분을 버리지도 바뀐 계정에 저장하지도 않는다.
    @Test("격리하지 못하면 입력 · 저장을 막은 채 다시 시도를 기다리고, 성공한 뒤에만 다시 연다")
    func quarantineFailureKeepsEverythingBlocked() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("disk")])
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        quarantine.failures.setValue(1)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        // 저장이 실패해 미저장분이 큐에 남아 있다.
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit("a")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)
        #expect(!store.state.pendingMutations.isEmpty)

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)
        guard case .failed = store.state.sessionEnd?.phase else {
            Issue.record("격리 실패가 남지 않았다: \(String(describing: store.state.sessionEnd))")
            return
        }
        #expect(!store.state.pendingMutations.isEmpty)
        #expect(!store.state.isInputEnabled)

        // 「다시 시도」 — 저장이 아니라 격리를 다시 한다.
        await store.send(.flushPending)
        await store.receive(\.sessionEndSettled)
        await store.receive(\.sessionQuarantineFinished)
        await store.receive(\.drawingsLoaded)

        #expect(quarantine.calls.value.count == 1)
        #expect(store.state.sessionEnd == nil)
        #expect(store.state.saveStatus == .idle)
        #expect(store.state.isInputEnabled)
        // 처음 실패한 저장 한 번뿐이다 — 바뀐 계정 아래로 다시 저장하지 않았다.
        #expect(spy.applied.value.count == 1)
        await end(store, environment)
    }

    // MARK: - 끊지 않는 경우

    /// 계정 변경 알림은 같은 계정에서도 온다.
    @Test("같은 계정으로 다시 확인되면 세션을 이어 가고 새 표를 든다")
    func sameAccountReconfirmationContinues() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)

        environment.change(to: confirmed(accountA, 2))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountA, 2))
        spy.releaseApply()
        await store.receive(\.saveFinished)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(quarantine.calls.value.isEmpty)
        await end(store, environment)
    }

    @Test("계정을 확인하는 중에는 세션을 끝내지 않고 근거도 바꾸지 않는다")
    func unconfirmedWhileCheckingKeepsSession() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)

        environment.change(to: DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                      knowledge: EraseEpochKnowledge()))
        await store.receive(\.editEnvironmentChanged)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        #expect(quarantine.calls.value.isEmpty)
        spy.releaseApply()
        await store.receive(\.saveFinished)
        await end(store, environment)
    }

    @Test("지킬 미저장분이 없으면 격리 없이 새 환경으로 다시 연다")
    func nothingToProtectJustReloads() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        let store = makeStore(spy: spy, results: [], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        let loadsBefore = spy.loadedChapters.value.count

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        #expect(quarantine.calls.value.isEmpty)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(spy.loadedChapters.value.count == loadsBefore + 1)
        #expect(store.state.isInputEnabled)
        await end(store, environment)
    }

    // MARK: - 사용자 전체 삭제

    /// 사용자가 요청한 전체 삭제는 미저장분을 버린다 — 닫던 세션의 것도 격리해 남기지 않는다.
    @Test("세션을 닫는 중에 전체 삭제가 오면 격리하지 않고 정리한다")
    func eraseAllDuringSessionEndSkipsQuarantine() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let quarantine = RecordingQuarantine()
        quarantine.failures.setValue(1)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, quarantine: quarantine)
        await composeAndSubscribe(store, environment)
        await holdOneEdit(store, spy)
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.sessionQuarantineFinished)

        await store.send(.drawingDataCleared)

        #expect(store.state.sessionEnd == nil)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.editEnvironment == confirmed(accountB, 2))
        #expect(quarantine.calls.value.isEmpty)
        spy.releaseApply()
        await end(store, environment)
    }
}
