//
//  DrawingEditEnvironment.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import CloudKit
import Dependencies
import Foundation

/// 편집이 기대는 환경 — 계정 상태 · 서버 작업 표 · `K(기기)` (정책 §12-6 구현 순서 ①).
///
/// 절 편집을 시작할 때 이 값으로 편집 문맥(`VerseEditContext`)을 고정하고, 바뀌면 문맥을 다시 판정한다.
public struct DrawingEditEnvironment: Equatable, Sendable {
    public var accountState: AccountScopeState
    /// 확인된 계정일 때만 있다.
    public var serverWork: AccountServerWorkToken?
    /// 지금 계정 근거의 `K(기기)`. 확인 전이면 마지막 확인 범위의 것(표시 · 문맥용 — 그동안 K 는 갱신하지 않는다),
    /// 로그인 안 함이면 이 기기 전용 범위의 것이다.
    ///
    /// **nil 은 읽지 못했다는 뜻이다** — 빈 집합(기준점 없음)과 다르다. 빈 집합으로 읽으면 삭제 사실을 잊은 환경이 된다.
    /// 읽지 못한 동안은 편집을 보존하되, 그 K 에 기대는 귀속 · 확정 · 정리는 하지 않는다.
    public var knowledge: EraseEpochKnowledge?
    /// 이 환경을 읽은 계정 확인 세대. 같은 세대 안에서 읽은 상태 · 표 · K 만 한 환경으로 묶는다.
    public var generation: UInt64

    public init(
        accountState: AccountScopeState,
        serverWork: AccountServerWorkToken?,
        knowledge: EraseEpochKnowledge?,
        generation: UInt64 = 0
    ) {
        self.accountState = accountState
        self.serverWork = serverWork
        self.knowledge = knowledge
        self.generation = generation
    }

    /// 이 환경에서 절 편집을 시작할 때의 계정 근거.
    public var accountBasis: VerseEditAccountBasis {
        switch accountState {
        case .confirmed:
            // 확인됨이면 표가 늘 있다. 없으면(경쟁으로 그 사이 무효가 됐다) 확인 전으로 다룬다.
            serverWork.map { .confirmed($0) } ?? .unverified(hint: nil)
        case .noAccount:
            .localOnly
        case .unconfirmed(let hint):
            .unverified(hint: hint)
        }
    }

    /// 확인 전 · 아무 정보도 없는 환경 — 서버 작업을 하지 않는 쪽이 기본이다. K 도 모른다.
    public static let unknown = DrawingEditEnvironment(
        accountState: .unconfirmed(lastConfirmed: nil),
        serverWork: nil,
        knowledge: nil
    )
}

public protocol DrawingEditEnvironmentClient: Sendable {
    /// 지금 환경.
    func current() async -> DrawingEditEnvironment
    /// 편집 문맥이 든 표가 아직 유효한가.
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool
    /// 환경이 바뀌었을 수 있다(계정 변경 알림 · 재확인 끝 · K 갱신). 받으면 `current()` 로 다시 읽고 문맥을 판정한다.
    func changes() -> AsyncStream<Void>
}

/// 앱이 쓰는 구현. 시작할 때 계정을 확인하고, 계정 변경 알림을 받으면 서버 작업을 막은 뒤 다시 확인한다.
///
/// - **환경은 한 확인 세대 안에서 읽는다.** 제공자에게서 상태 · 표 · 세대를 한 번에 받고(`AccountScopeProvider.snapshot`),
///   그 범위의 K 를 읽은 뒤 세대가 그대로인지 확인한다. 바뀌었으면 다시 읽고, 계속 바뀌면 확인 대기 환경을 준다.
/// - **알림 콜백 안에서 동기로 막는다.** 콜백이 돌아온 뒤 제공자를 무효화하기까지의 틈에도 옛 표가 쓰이지 않게,
///   그 사이에는 `isCurrent` 가 거짓이고 `current()` 가 확인 대기 환경을 준다.
public final class LiveDrawingEditEnvironment: DrawingEditEnvironmentClient, @unchecked Sendable {
    private let provider: AccountScopeProvider
    private let stateStore: FileEraseStateStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var observation: (any NSObjectProtocol)?
    /// 받았지만 아직 제공자에 반영하지 못한 계정 변경 알림 수.
    private var unappliedNotifications = 0

    /// 한 번에 읽는 시도 횟수. 계정이 계속 바뀌면 확인 대기로 둔다.
    static let maxSnapshotAttempts = 3

    public init(
        identity: any CloudAccountIdentityClient,
        containerID: String,
        stateStore: FileEraseStateStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.provider = AccountScopeProvider(identity: identity, containerID: containerID, stateStore: stateStore)
        self.stateStore = stateStore
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let observation { notificationCenter.removeObserver(observation) }
    }

    /// 계정 변경 알림을 구독하고 계정을 확인한다. 앱이 시작할 때 한 번 부른다.
    public func start() async {
        lock.lock()
        if observation == nil {
            // ★ 알림을 **동기로** 구독한다 — 확인하는 동안 온 알림을 놓치지 않는다.
            observation = notificationCenter.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
                self?.accountChangeNotified()
            }
        }
        lock.unlock()
        await provider.refresh()
        notifySubscribers()
    }

    /// 알림 콜백 — **여기서 동기로** 막고 알린 뒤, 제공자 무효화 · 재확인은 뒤이어 한다.
    func accountChangeNotified() {
        lock.lock()
        unappliedNotifications += 1
        lock.unlock()
        notifySubscribers()
        Task { await self.applyAccountChange() }
    }

    private func applyAccountChange() async {
        await provider.invalidate()
        lock.lock()
        unappliedNotifications -= 1
        lock.unlock()
        notifySubscribers()
        await provider.refresh()
        notifySubscribers()
    }

    private var hasUnappliedNotification: Bool {
        lock.lock()
        defer { lock.unlock() }
        return unappliedNotifications > 0
    }

    /// `K(기기)` 가 바뀌었다(기준점 수신 등). 편집 문맥을 다시 판정하게 알린다.
    public func knowledgeDidChange() {
        notifySubscribers()
    }

    public func current() async -> DrawingEditEnvironment {
        for _ in 0..<Self.maxSnapshotAttempts {
            guard !hasUnappliedNotification else { break }
            let snapshot = await provider.snapshot()
            let knowledge = readKnowledge(for: snapshot.state)
            // K 를 읽는 사이 계정이 바뀌지 않았어야 한 환경이다.
            if await provider.isGeneration(snapshot.generation), !hasUnappliedNotification {
                return DrawingEditEnvironment(
                    accountState: snapshot.state, serverWork: snapshot.token, knowledge: knowledge, generation: snapshot.generation
                )
            }
        }
        // 계정이 바뀌는 중이다 — 표 없이 확인 대기로 둔다. K 도 이 세대의 것이라 말할 수 없다.
        let snapshot = await provider.snapshot()
        return DrawingEditEnvironment(
            accountState: .unconfirmed(lastConfirmed: snapshot.state.lastConfirmedHint),
            serverWork: nil,
            knowledge: nil,
            generation: snapshot.generation
        )
    }

    /// 상태에 맞는 범위의 K. 파일이 없으면 빈 집합(기준점 없음), **읽지 못하면 nil** 이다.
    private func readKnowledge(for state: AccountScopeState) -> EraseEpochKnowledge? {
        let scope: AccountScope? = switch state {
        case .confirmed(let scope): scope
        case .noAccount: .localOnly
        case .unconfirmed(let hint): hint
        }
        // 확인한 적이 없는 기기 — 받은 기준점이 없다.
        guard let scope else { return EraseEpochKnowledge() }
        do {
            return try stateStore.knowledge(for: scope)
        } catch {
            Log.error("편집 환경 — K(기기)를 읽지 못했다. 빈 집합으로 두지 않는다", "\(error)")
            return nil
        }
    }

    public func isCurrent(_ token: AccountServerWorkToken) async -> Bool {
        guard !hasUnappliedNotification else { return false }
        return await provider.isCurrent(token)
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            subscribers[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.subscribers.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    private func notifySubscribers() {
        lock.lock()
        let continuations = Array(subscribers.values)
        lock.unlock()
        continuations.forEach { $0.yield() }
    }
}

/// 정해 둔 환경을 돌려주는 구현. 변화 알림은 곧바로 끝난다 — 시험의 효과가 남지 않게.
public struct StubDrawingEditEnvironment: DrawingEditEnvironmentClient {
    private let environment: DrawingEditEnvironment

    public init(_ environment: DrawingEditEnvironment) {
        self.environment = environment
    }

    public func current() async -> DrawingEditEnvironment { environment }
    public func isCurrent(_ token: AccountServerWorkToken) async -> Bool { environment.serverWork == token }
    public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private enum DrawingEditEnvironmentKey: DependencyKey {
    /// 앱이 `LiveDrawingEditEnvironment` 를 주입한다. 주입하지 않았으면 확인 전 환경 — 서버 작업을 하지 않는다.
    static let liveValue: any DrawingEditEnvironmentClient = StubDrawingEditEnvironment(.unknown)
    static let testValue: any DrawingEditEnvironmentClient = StubDrawingEditEnvironment(.unknown)
}

public extension DependencyValues {
    /// 편집이 기대는 계정 · K 환경.
    var drawingEditEnvironment: any DrawingEditEnvironmentClient {
        get { self[DrawingEditEnvironmentKey.self] }
        set { self[DrawingEditEnvironmentKey.self] = newValue }
    }
}
