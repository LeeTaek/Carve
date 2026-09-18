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
    public var knowledge: EraseEpochKnowledge

    public init(accountState: AccountScopeState, serverWork: AccountServerWorkToken?, knowledge: EraseEpochKnowledge) {
        self.accountState = accountState
        self.serverWork = serverWork
        self.knowledge = knowledge
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

    /// 확인 전 · 아무 정보도 없는 환경 — 서버 작업을 하지 않는 쪽이 기본이다.
    public static let unknown = DrawingEditEnvironment(
        accountState: .unconfirmed(lastConfirmed: nil),
        serverWork: nil,
        knowledge: EraseEpochKnowledge()
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

/// 앱이 쓰는 구현. 시작할 때 계정을 확인하고, 계정 변경 알림을 받으면 **즉시** 서버 작업을 잠근 뒤 다시 확인한다.
public final class LiveDrawingEditEnvironment: DrawingEditEnvironmentClient, @unchecked Sendable {
    private let provider: AccountScopeProvider
    private let stateStore: FileEraseStateStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var observation: (any NSObjectProtocol)?

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
                guard let self else { return }
                Task { await self.accountMayHaveChanged() }
            }
        }
        lock.unlock()
        await provider.refresh()
        notifySubscribers()
    }

    /// 계정이 바뀌었을 수 있다 — 잠그고 알린 뒤 다시 확인하고 한 번 더 알린다.
    func accountMayHaveChanged() async {
        await provider.invalidate()
        notifySubscribers()
        await provider.refresh()
        notifySubscribers()
    }

    /// `K(기기)` 가 바뀌었다(기준점 수신 등). 편집 문맥을 다시 판정하게 알린다.
    public func knowledgeDidChange() {
        notifySubscribers()
    }

    public func current() async -> DrawingEditEnvironment {
        let state = await provider.state
        let token = await provider.serverWorkToken()
        let knowledgeScope: AccountScope? = switch state {
        case .confirmed(let scope): scope
        case .noAccount: .localOnly
        case .unconfirmed(let hint): hint
        }
        var knowledge = EraseEpochKnowledge()
        if let knowledgeScope {
            do {
                knowledge = try stateStore.knowledge(for: knowledgeScope)
            } catch {
                Log.error("편집 환경 — K(기기)를 읽지 못했다", "\(error)")
            }
        }
        return DrawingEditEnvironment(accountState: state, serverWork: token, knowledge: knowledge)
    }

    public func isCurrent(_ token: AccountServerWorkToken) async -> Bool {
        await provider.isCurrent(token)
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
