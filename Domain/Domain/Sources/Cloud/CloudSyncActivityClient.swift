//
//  CloudSyncActivityClient.swift
//  Domain
//
//  앱이 도는 동안의 동기화 활동을 화면에 흘려보낸다 (정책 §4-1).
//

import Foundation

import Dependencies

/// 동기화 활동을 구독한다. 화면이 `PersistentCloudKitContainer` 를 직접 알지 않게 하는 경계다.
///
/// - Important: 활동은 **이번 실행**의 기록이다. 저장하지 않으므로 앱을 방금 켰다면 비어 있고,
///              그것이 "동기화되지 않았다" 는 뜻은 아니다.
public protocol CloudSyncActivityClient: Sendable {
    /// 현재 값부터 시작해 바뀔 때마다 새 값을 보낸다.
    func activities() -> AsyncStream<CloudSyncActivity>
}

/// 앱이 실제로 쓰는 구현. `PersistentCloudKitContainer.activity` 를 그대로 흘려보낸다.
public struct LiveCloudSyncActivityClient: CloudSyncActivityClient {
    public init() { }

    public func activities() -> AsyncStream<CloudSyncActivity> {
        @Dependency(\.clouodKitSyncManager) var container
        let publisher = container.$activity
        return AsyncStream { continuation in
            let task = Task {
                for await value in publisher.values {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 정해 둔 값들을 차례로 보내고 끝나는 구현. 테스트·프리뷰용이다.
public struct StubCloudSyncActivityClient: CloudSyncActivityClient {
    private let values: [CloudSyncActivity]

    public init(_ values: [CloudSyncActivity]) {
        self.values = values
    }

    public func activities() -> AsyncStream<CloudSyncActivity> {
        AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

private enum CloudSyncActivityClientKey: DependencyKey {
    static let liveValue: any CloudSyncActivityClient = LiveCloudSyncActivityClient()
    static let testValue: any CloudSyncActivityClient = StubCloudSyncActivityClient([])
    static let previewValue: any CloudSyncActivityClient = StubCloudSyncActivityClient([CloudSyncActivity()])
}

public extension DependencyValues {
    /// 앱이 도는 동안의 동기화 활동.
    var cloudSyncActivity: any CloudSyncActivityClient {
        get { self[CloudSyncActivityClientKey.self] }
        set { self[CloudSyncActivityClientKey.self] = newValue }
    }
}
