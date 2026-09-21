//
//  Concurrency+Extensions.swift
//  Core
//
//  Created by 이택성 on 3/6/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

/// `Task.withTimeout` 의 제한 시간이 지났다.
///
/// 호출부가 **시간 초과만** 골라낼 수 있게 타입으로 던진다. 이전에는 도메인 문자열이 "TimeoutError" 인 `NSError` 라
/// 호출부가 오류를 구분하지 않고 한 `catch` 로 받았고, 계정 조회 실패 · 취소까지 시간 초과로 다뤘다.
public struct TaskTimeoutError: Error, Equatable, Sendable {
    public let seconds: Double

    public init(seconds: Double) {
        self.seconds = seconds
    }
}

extension Task where Success == Never, Failure == Never {
    /// 주어진 비동기 작업을 실행하고, 제한 시간이 지나면 `TaskTimeoutError` 를 던진다.
    /// 작업 자신의 오류와 취소(`CancellationError`)는 그대로 전해진다.
    public static func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TaskTimeoutError(seconds: seconds)
            }

            guard let result = try await group.next() else {
                throw TaskTimeoutError(seconds: seconds)
            }
            group.cancelAll()
            return result
        }
    }
}
