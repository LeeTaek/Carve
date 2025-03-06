//
//  Concurrency+Extensions.swift
//  Core
//
//  Created by 이택성 on 3/6/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

extension Task where Success == Never, Failure == Never {
    // 주어진 비동기 작업을 실행하고, 특정 시간이 초과되면 예외 처리.
    public static func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task timed out"])
            }

            guard let result = try await group.next() else {
                throw NSError(domain: "TimeoutError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task timed out"])
            }
            group.cancelAll()
            return result
        }
    }
}
