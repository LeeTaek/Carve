//
//  AccountScopeTesting.swift
//  DomainTest
//
//  계정 범위 — 무엇으로 키를 만들고, 확인하지 못했을 때 무엇을 막는가 (정책 §12-6 계정 범위).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 확인하지 못한 계정 · 이전 계정의 표로 서버 작업을 하는 것(다른 계정의 필사를 지울 수 있다, S13)
/// - 늦게 온 조회 결과가 최신 계정 확인을 덮는 것
/// - 출처를 증명하지 못한 로컬 보존을 어느 계정에 자동으로 붙이는 것
/// 반대로 확인 전이라고 로컬 보존까지 막으면 오프라인 첫 실행의 필기를 잃으므로, 로컬 보존은 늘 한다.
@Suite("계정 범위")
struct AccountScopeTesting {

    private let container = "iCloud.Carve.SwiftData.iCloud.dev"

    /// 조회할 때마다 정해 둔 결과를 차례로 돌려준다. `gated` 에 든 차례는 `release` 할 때까지 돌아오지 않는다.
    private actor GatedIdentityClient: CloudAccountIdentityClient {
        private let results: [CloudAccountIdentity]
        private let gated: Set<Int>
        private var released: Set<Int> = []
        private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
        private(set) var calls = 0

        init(_ results: [CloudAccountIdentity], gated: Set<Int> = []) {
            self.results = results
            self.gated = gated
        }

        func currentIdentity() async -> CloudAccountIdentity {
            let index = calls
            calls += 1
            if gated.contains(index), !released.contains(index) {
                await withCheckedContinuation { waiting[index] = $0 }
            }
            return index < results.count ? results[index] : .unavailable
        }

        func release(_ index: Int) {
            released.insert(index)
            waiting.removeValue(forKey: index)?.resume()
        }
    }

    private func withStateStore(_ body: (FileEraseStateStore, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("account-scope-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileEraseStateStore(area: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite"))
        try await body(store, root)
    }

    private func scope(_ name: String) -> AccountScope {
        .make(containerID: container, userRecordName: name)
    }

    // MARK: - 키와 판정

    @Test("확인한 계정 · 로그인 안 함 · 확인 못 함을 가른다")
    func resolverTable() {
        let last = AccountScope(key: "acct-last")

        #expect(AccountScopeResolver.resolve(.identified(userRecordName: "_user"), containerID: container, lastConfirmed: last)
            == .confirmed(scope("_user")))
        #expect(AccountScopeResolver.resolve(.noAccount, containerID: container, lastConfirmed: last) == .noAccount)
        // 조회 실패는 "계정 없음" 이 아니다. 마지막 확인 범위는 참고로만 든다.
        #expect(AccountScopeResolver.resolve(.unavailable, containerID: container, lastConfirmed: last) == .unconfirmed(lastConfirmed: last))
    }

    /// 사용자 레코드 이름은 컨테이너마다 다르다. dev · 운영 컨테이너의 상태가 섞이지 않아야 한다.
    @Test("같은 사용자 레코드 이름이어도 컨테이너가 다르면 다른 범위다")
    func scopeIncludesContainer() {
        let dev = AccountScope.make(containerID: "iCloud.Carve.SwiftData.iCloud.dev", userRecordName: "_user")
        let production = AccountScope.make(containerID: "iCloud.Carve.SwiftData.iCloud", userRecordName: "_user")

        #expect(dev != production)
        #expect(!dev.key.contains("_user"))
    }

    /// 앱을 끈 사이 시스템에서 계정을 바꿨을 수 있다. 마지막 확인 범위는 저장소 내용의 소유를 증명하지 못한다.
    @Test("서버 작업은 확인된 계정만 하고, 출처를 증명하지 못한 로컬 보존은 계정에 붙이지 않는다")
    func stateSeparatesServerWorkFromLocalPreservation() {
        let account = AccountScope(key: "acct-a")

        #expect(AccountScopeState.confirmed(account).scopeForServerWork == account)
        #expect(AccountScopeState.confirmed(account).scopeForLocalPreservation == account)
        #expect(AccountScopeState.unconfirmed(lastConfirmed: account).scopeForServerWork == nil)
        #expect(AccountScopeState.unconfirmed(lastConfirmed: account).scopeForLocalPreservation == .unverified)
        #expect(AccountScopeState.noAccount.scopeForServerWork == nil)
        #expect(AccountScopeState.noAccount.scopeForLocalPreservation == .localOnly)
    }

    // MARK: - 앱이 쥐는 범위

    @Test("확인한 범위를 기억하되, 다음 실행에서 확인하지 못하면 서버 작업을 막고 미확인 묶음에 보존한다")
    func remembersConfirmedScopeOnlyAsHint() async throws {
        try await withStateStore { store, _ in
            let first = AccountScopeProvider(identity: GatedIdentityClient([.identified(userRecordName: "_user")]), containerID: container, stateStore: store)
            #expect(await first.refresh() == .confirmed(scope("_user")))

            // 다음 실행 — 오프라인이라 확인하지 못한다.
            let second = AccountScopeProvider(identity: GatedIdentityClient([.unavailable]), containerID: container, stateStore: store)
            let state = await second.refresh()

            #expect(state == .unconfirmed(lastConfirmed: scope("_user")))
            #expect(state.scopeForServerWork == nil)
            #expect(state.scopeForLocalPreservation == .unverified)
        }
    }

    /// A 조회가 늦는 사이 B 로 바뀌어 B 조회가 먼저 끝났다. 늦게 온 A 결과가 B 를 덮으면 이전 계정으로 서버 작업을 한다.
    @Test("재확인하는 동안 서버 작업을 잠그고, 늦게 온 조회 결과는 버린다")
    func discardsStaleIdentityResult() async throws {
        try await withStateStore { store, _ in
            let client = GatedIdentityClient([.identified(userRecordName: "_a"), .identified(userRecordName: "_b")], gated: [0])
            let provider = AccountScopeProvider(identity: client, containerID: container, stateStore: store)

            let slow = Task { await provider.refresh() }
            while await client.calls < 1 { await Task.yield() }
            // 첫 조회를 기다리는 동안은 서버 작업을 할 수 없다.
            #expect(await provider.serverWorkToken() == nil)

            let fast = await provider.refresh()
            #expect(fast == .confirmed(scope("_b")))

            await client.release(0)
            let stale = await slow.value

            #expect(stale == .confirmed(scope("_b")))
            #expect(await provider.state == .confirmed(scope("_b")))
            let remembered = try store.lastConfirmedScope()
            #expect(remembered == scope("_b"))
        }
    }

    @Test("계정 변경 알림을 받으면 진행 중인 작업의 표가 무효가 되고, 다시 확인해야 새 표를 준다")
    func invalidationRevokesServerWorkTokens() async throws {
        try await withStateStore { store, _ in
            let client = GatedIdentityClient([.identified(userRecordName: "_a"), .identified(userRecordName: "_a")])
            let provider = AccountScopeProvider(identity: client, containerID: container, stateStore: store)
            await provider.refresh()
            let token = try #require(await provider.serverWorkToken())
            #expect(await provider.isCurrent(token))

            await provider.invalidate()
            #expect(await !provider.isCurrent(token))
            #expect(await provider.serverWorkToken() == nil)

            // 같은 계정으로 다시 확인해도 옛 표는 되살아나지 않는다 — 작업은 새 표를 받아 다시 시작한다.
            await provider.refresh()
            #expect(await !provider.isCurrent(token))
            let renewed = try #require(await provider.serverWorkToken())
            #expect(renewed.scope == token.scope)
            #expect(await provider.isCurrent(renewed))
        }
    }

    @Test("확인 전 · 로그인 안 함 동안 남긴 복구 사본은 계정이 확인돼도 자동으로 옮기지 않는다")
    func doesNotAttributeUnverifiedCopies() async throws {
        try await withStateStore { store, root in
            let recovery = FileRecoveryCopyStore(root: root.appendingPathComponent("Recovery", isDirectory: true))
            for bucket in [AccountScope.unverified, .localOnly] {
                try recovery.save(
                    RecoveryCopyEntry(kind: .version, accountScope: bucket.key, verseKey: "NKRV/1-01Genesis.txt/1/1",
                                      contentFingerprint: "vc1-\(bucket.key)", deviceID: "device-1"),
                    blob: Data(bucket.key.utf8)
                )
            }
            let provider = AccountScopeProvider(identity: GatedIdentityClient([.identified(userRecordName: "_a")]), containerID: container, stateStore: store)

            await provider.refresh()

            #expect(try recovery.entries(accountScope: AccountScope.unverified.key).count == 1)
            #expect(try recovery.entries(accountScope: AccountScope.localOnly.key).count == 1)
            #expect(try recovery.entries(accountScope: scope("_a").key).isEmpty)
        }
    }

    @Test("로그인하지 않은 기기는 서버 작업을 하지 않는다")
    func noAccountDoesNoServerWork() async throws {
        try await withStateStore { store, _ in
            let provider = AccountScopeProvider(identity: GatedIdentityClient([.noAccount]), containerID: container, stateStore: store)

            #expect(await provider.refresh() == .noAccount)
            #expect(await provider.serverWorkToken() == nil)
        }
    }
}
