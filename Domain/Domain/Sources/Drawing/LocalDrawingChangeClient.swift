//
//  LocalDrawingChangeClient.swift
//  Domain
//
//  Created by Claude on 9/29/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// 이 기기에서 **필사 화면 밖**이 저장소의 한 장을 바꿨다 — 「확인이 필요한 필기」 의 가져오기(2026-09-29).
///
/// 설정은 필사 화면 위에 패널로 뜨므로 그 아래의 열린 장은 이 쓰기를 모른다. iCloud 에서 받은 필사(`CloudImportArrivalClient`)와 같은 길로
/// 반영하게, 바뀐 장과 시각을 알린다 — 받는 쪽이 그 장이면 저장소를 다시 읽어 반영한다.
public struct LocalDrawingChange: Equatable, Sendable {
    public let chapter: BibleChapter
    /// 저장을 마친 시각 — 그보다 늦게 시작한 조회에는 이미 들어 있다.
    public let date: Date

    public init(chapter: BibleChapter, date: Date) {
        self.chapter = chapter
        self.date = date
    }
}

public protocol LocalDrawingChangeClient: Sendable {
    /// 바뀌었다고 알린다. 받는 쪽이 없으면 버린다 — 새로 여는 장은 어차피 저장소를 읽는다.
    func post(_ change: LocalDrawingChange)
    func changes() -> AsyncStream<LocalDrawingChange>
}

/// 앱이 쓰는 구현 — 구독한 모두에게 보낸다.
public final class LiveLocalDrawingChangeClient: LocalDrawingChangeClient, @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<LocalDrawingChange>.Continuation] = [:]

    public init() { }

    public func post(_ change: LocalDrawingChange) {
        lock.lock()
        let continuations = Array(subscribers.values)
        lock.unlock()
        continuations.forEach { $0.yield(change) }
    }

    public func changes() -> AsyncStream<LocalDrawingChange> {
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
}

/// 아무것도 보내지 않는 구현 — 시험 · 미리보기의 기본값. 구독은 곧바로 끝난다(시험의 효과가 남지 않게).
public struct StubLocalDrawingChangeClient: LocalDrawingChangeClient {
    public init() { }

    public func post(_ change: LocalDrawingChange) { }
    public func changes() -> AsyncStream<LocalDrawingChange> { AsyncStream { $0.finish() } }
}

private enum LocalDrawingChangeClientKey: DependencyKey {
    static let liveValue: any LocalDrawingChangeClient = LiveLocalDrawingChangeClient()
    static let testValue: any LocalDrawingChangeClient = StubLocalDrawingChangeClient()
    static let previewValue: any LocalDrawingChangeClient = StubLocalDrawingChangeClient()
}

public extension DependencyValues {
    /// 필사 화면 밖에서 저장소의 한 장을 바꿨다는 신호.
    var localDrawingChanges: any LocalDrawingChangeClient {
        get { self[LocalDrawingChangeClientKey.self] }
        set { self[LocalDrawingChangeClientKey.self] = newValue }
    }
}
