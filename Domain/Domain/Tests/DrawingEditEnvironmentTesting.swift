//
//  DrawingEditEnvironmentTesting.swift
//  DomainTest
//
//  편집 환경 — 계정 상태 · 서버 작업 표 · K(기기)를 한 곳에서 주고, 계정 변경 알림에 즉시 잠근다 (정책 §12-6 구현 순서 ①).
//

import CloudKit
import Foundation
import Testing

@testable import Domain

@Suite("편집 환경")
struct DrawingEditEnvironmentTesting {

    private let container = "iCloud.Carve.SwiftData.iCloud.dev"

    private actor SequencedIdentityClient: CloudAccountIdentityClient {
        private var values: [CloudAccountIdentity]

        init(_ values: [CloudAccountIdentity]) {
            self.values = values
        }

        func currentIdentity() async -> CloudAccountIdentity {
            values.isEmpty ? .unavailable : values.removeFirst()
        }
    }

    private func withStateStore(_ body: (FileEraseStateStore) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("edit-env-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(FileEraseStateStore(area: EraseStateArea(root: root, storeFileName: "Carve.sqlite")))
    }

    private func scope(_ name: String) -> AccountScope {
        .make(containerID: container, userRecordName: name)
    }

    @Test("확인된 계정이면 표와 그 계정의 K 를 주고, 편집 문맥은 그 표에 기댄다")
    func confirmedEnvironment() async throws {
        try await withStateStore { store in
            try store.recordReceived("E1", knownAtCreation: [], for: scope("_a"))
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )

            await environment.start()
            let current = await environment.current()

            #expect(current.accountState == .confirmed(scope("_a")))
            let token = try #require(current.serverWork)
            #expect(current.accountBasis == .confirmed(token))
            #expect(current.knowledge.received == ["E1"])
            #expect(await environment.isCurrent(token))
        }
    }

    /// 확인 전에는 서버 작업을 하지 않지만, 화면 · 문맥에 쓸 K 는 마지막 확인 범위의 것을 준다 — 그동안 K 는 갱신되지 않는다.
    @Test("확인하지 못하면 표 없이, 마지막 확인 범위를 참고로 든 문맥 근거를 준다")
    func unconfirmedEnvironment() async throws {
        try await withStateStore { store in
            try store.rememberConfirmedScope(scope("_a"))
            try store.recordReceived("E1", knownAtCreation: [], for: scope("_a"))
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.unavailable]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )

            await environment.start()
            let current = await environment.current()

            #expect(current.serverWork == nil)
            #expect(current.accountBasis == .unverified(hint: scope("_a")))
            #expect(current.knowledge.received == ["E1"])
        }
    }

    @Test("로그인하지 않았으면 이 기기 전용 근거와 그 범위의 K 를 준다")
    func noAccountEnvironment() async throws {
        try await withStateStore { store in
            try store.recordReceived("E-local", knownAtCreation: [], for: .localOnly)
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.noAccount]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )

            await environment.start()
            let current = await environment.current()

            #expect(current.accountBasis == .localOnly)
            #expect(current.serverWork == nil)
            #expect(current.knowledge.received == ["E-local"])
        }
    }

    /// 계정 변경 알림을 받으면 확인이 끝나기 전에도 표가 무효다 — 그 사이 확정 · 서버 정리를 하지 않는다.
    @Test("계정 변경 알림을 받으면 즉시 표를 무효로 하고, 다시 확인한 뒤 알린다")
    func accountChangeNotification() async throws {
        try await withStateStore { store in
            let center = NotificationCenter()
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a"), .identified(userRecordName: "_b")]),
                containerID: container, stateStore: store, notificationCenter: center
            )
            await environment.start()
            let before = try #require(await environment.current().serverWork)
            var changes = environment.changes().makeAsyncIterator()

            center.post(name: .CKAccountChanged, object: nil)

            // 잠금 알림과 재확인 알림, 두 번 온다.
            _ = await changes.next()
            _ = await changes.next()
            #expect(await !environment.isCurrent(before))
            let after = await environment.current()
            #expect(after.accountState == .confirmed(scope("_b")))
            let renewed = try #require(after.serverWork)
            #expect(await environment.isCurrent(renewed))
        }
    }

    @Test("주입하지 않은 기본값은 확인 전 환경이다 — 서버 작업을 하지 않는다")
    func unconfiguredDefaultDoesNoServerWork() async {
        let current = await StubDrawingEditEnvironment(.unknown).current()

        #expect(current.serverWork == nil)
        #expect(current.accountBasis == .unverified(hint: nil))
    }
}
