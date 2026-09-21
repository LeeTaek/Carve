//
//  CloudImportArrivalClient.swift
//  Domain
//
//  import 가 성공으로 끝날 때마다 열린 장에 알린다 — 늦게 도착한 필사를 반영하는 입구 (2026-09-21 후속 리뷰 P0-3, 사용자 결정).
//

import Combine
import Foundation

import Dependencies

/// iCloud 에서 받은 필사가 **이 기기 저장소에 들어왔을 수 있다**는 신호.
///
/// import 가 성공으로 끝나면(`CloudSyncActivity.lastImportSuccess` 가 바뀌면) 그 시각을 보낸다. 받는 쪽(열린 장)은 그 시각이 자기 조회보다
/// 늦을 때만 "도착했을 수 있다" 로 보고, 저장소만 다시 읽어 그 장이 실제로 바뀌었는지 가린다 — 이 신호는 어느 장이 바뀌었는지 모른다.
///
/// - Important: **구독 시점의 마지막 성공도 한 번 보낸다.** 조회와 구독이 동시에 시작되므로, 조회가 읽은 뒤 · 구독이 걸리기 전에 끝난
///              import 를 놓치지 않으려는 것이다. 받는 쪽이 시각으로 이미 반영된 것을 거른다.
public protocol CloudImportArrivalClient: Sendable {
    func arrivals() -> AsyncStream<Date>
}

/// 앱이 쓰는 구현 — 앱 수명 동안 도는 CloudKit 이벤트 관찰(`PersistentCloudKitContainer.activity`)을 그대로 쓴다.
public struct LiveCloudImportArrivalClient: CloudImportArrivalClient {
    public init() { }

    public func arrivals() -> AsyncStream<Date> {
        @Dependency(\.clouodKitSyncManager) var container
        // 받는 쪽이 한 값을 처리하는 사이 온 값을 버리지 않게 담아 둔다 — `values` 는 기다리는 소비자가 없으면 값을 버린다. 놓치면 마지막 import
        // 성공이 다음 변화까지 전해지지 않는다.
        let publisher = container.$activity.buffer(size: 16, prefetch: .keepFull, whenFull: .dropOldest)
        return AsyncStream { continuation in
            let task = Task {
                var last: Date?
                for await activity in publisher.values {
                    guard let success = activity.lastImportSuccess, success != last else { continue }
                    last = success
                    continuation.yield(success)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 정해 둔 시각들을 보내고 끝나는 구현. 시험 · 미리보기용이다 — 기본은 아무것도 보내지 않는다.
public struct StubCloudImportArrivalClient: CloudImportArrivalClient {
    private let dates: [Date]

    public init(_ dates: [Date] = []) {
        self.dates = dates
    }

    public func arrivals() -> AsyncStream<Date> {
        AsyncStream { continuation in
            for date in dates { continuation.yield(date) }
            continuation.finish()
        }
    }
}

private enum CloudImportArrivalClientKey: DependencyKey {
    static let liveValue: any CloudImportArrivalClient = LiveCloudImportArrivalClient()
    static let testValue: any CloudImportArrivalClient = StubCloudImportArrivalClient()
    static let previewValue: any CloudImportArrivalClient = StubCloudImportArrivalClient()
}

public extension DependencyValues {
    /// iCloud 에서 받은 필사가 저장소에 들어왔을 수 있다는 신호(import 성공 시각).
    var cloudImportArrivals: any CloudImportArrivalClient {
        get { self[CloudImportArrivalClientKey.self] }
        set { self[CloudImportArrivalClientKey.self] = newValue }
    }
}
