//
//  TaskTimeoutTesting.swift
//  CarveToolkitTest
//
//  `Task.withTimeout` 이 던지는 것 — 호출부가 시간 초과만 골라낼 수 있어야 한다.
//

@testable import CarveToolkit
import Foundation
import Testing

struct TaskTimeoutTesting {
    private struct Boom: Error, Equatable {}

    @Test("제한 시간이 지나면 TaskTimeoutError 를 던진다")
    func timeoutIsTyped() async {
        await #expect(throws: TaskTimeoutError(seconds: 0.05)) {
            try await Task.withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(5))
            }
        }
    }

    @Test("작업이 먼저 끝나면 그 결과를 돌려준다")
    func returnsResultBeforeTimeout() async throws {
        let value = try await Task.withTimeout(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test("작업 자신의 오류는 시간 초과로 바꾸지 않는다")
    func operationErrorPassesThrough() async {
        await #expect(throws: Boom()) {
            try await Task.withTimeout(seconds: 5) { throw Boom() }
        }
    }
}
