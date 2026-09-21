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
            #expect(current.knowledge?.received == ["E1"])
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
            #expect(current.knowledge?.received == ["E1"])
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
            #expect(current.knowledge?.received == ["E-local"])
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

    /// 읽지 못한 K 를 빈 집합으로 주면 삭제 사실을 잊은 환경이 된다.
    @Test("K 파일을 읽지 못하면 빈 집합이 아니라 읽지 못함(nil)으로 준다")
    func unreadableKnowledgeIsNotEmpty() async throws {
        try await withStateStore { store in
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )
            await environment.start()
            try store.recordReceived("E1", knownAtCreation: [], for: scope("_a"))
            let file = store.areaForTesting.scopeDirectory(scope("_a").key).appendingPathComponent("erase-knowledge.json")
            try Data("깨진 값".utf8).write(to: file)

            let current = await environment.current()

            #expect(current.knowledge == nil)
            // 계정 근거는 그대로 준다 — 보존은 이어 가고, K 에 기대는 판정만 보류한다.
            #expect(current.accountState == .confirmed(scope("_a")))
        }
    }

    /// 콜백이 돌아온 뒤 제공자를 무효화하기까지의 틈에도 옛 표가 쓰이면 안 된다.
    @Test("알림 콜백이 돌아온 바로 뒤에도 옛 표는 무효이고, 환경은 옛 표를 주지 않는다")
    func notificationBlocksSynchronously() async throws {
        try await withStateStore { store in
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a"), .identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )
            await environment.start()
            let before = try #require(await environment.current().serverWork)

            environment.accountChangeNotified()

            #expect(await !environment.isCurrent(before))
            #expect(await environment.current().serverWork != before)
        }
    }

    @Test("환경의 상태 · 표 · 세대는 한 확인 세대에서 읽은 것이다")
    func environmentIsReadFromOneGeneration() async throws {
        try await withStateStore { store in
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )
            await environment.start()

            let current = await environment.current()
            let token = try #require(current.serverWork)

            #expect(token.generation == current.generation)
            #expect(current.accountState == .confirmed(token.scope))
        }
    }

    /// 확인하지 못한 채 보존만 하다가 영구히 머물지 않아야 한다(7차 리뷰).
    @Test("앱이 다시 활성화되면 확인하지 못한 계정을 다시 확인하고 알린다")
    func reactivationReevaluates() async throws {
        try await withStateStore { store in
            let center = NotificationCenter()
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.unavailable, .identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: center
            )
            await environment.start()
            #expect(await environment.current().serverWork == nil)
            var changes = environment.changes().makeAsyncIterator()

            center.post(name: LiveDrawingEditEnvironment.didBecomeActiveNotification, object: nil)
            _ = await changes.next()

            #expect(await environment.current().accountState == .confirmed(scope("_a")))
        }
    }

    @Test("저장소 소유 근거는 검증된 방법이 정해질 때까지 비어 있다 — 모든 세션이 보존만 한다")
    func storeOwnershipIsNotClaimedYet() async throws {
        try await withStateStore { store in
            let environment = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter()
            )
            await environment.start()

            #expect(await environment.current().storeOwnership == nil)
        }
    }

    // MARK: - 동기화 저장소에 바로 쓰는 경로의 판정 (정책 §12-6 결정 1)

    @Test("동기화 쓰기는 확인된 계정 · 표 · K · 그 계정의 저장소 소유 근거가 모두 있을 때만 연다")
    func syncedWriteBlockTable() {
        let owner = scope("_a")
        let other = scope("_b")
        let token = AccountServerWorkToken(scope: owner, generation: 1)
        func environment(
            _ state: AccountScopeState, _ work: AccountServerWorkToken?, _ knowledge: EraseEpochKnowledge?, _ owner: AccountScope?
        ) -> DrawingEditEnvironment {
            DrawingEditEnvironment(accountState: state, serverWork: work, knowledge: knowledge, storeOwnership: owner)
        }

        #expect(SyncedWriteBlock.check(environment(.noAccount, nil, EraseEpochKnowledge(), nil)) == .signedOut)
        #expect(SyncedWriteBlock.check(environment(.unconfirmed(lastConfirmed: owner), nil, EraseEpochKnowledge(), owner)) == .accountUnconfirmed)
        // 확인은 됐지만 표가 없다 — 그 계정으로 서버 작업을 할 수 없다.
        #expect(SyncedWriteBlock.check(environment(.confirmed(owner), nil, EraseEpochKnowledge(), owner)) == .accountUnconfirmed)
        #expect(SyncedWriteBlock.check(environment(.confirmed(owner), token, nil, owner)) == .knowledgeUnreadable)
        #expect(SyncedWriteBlock.check(environment(.confirmed(owner), token, EraseEpochKnowledge(), nil)) == .ownershipUnverified)
        // 소유 근거가 **다른** 계정의 것이면 막는다.
        #expect(SyncedWriteBlock.check(environment(.confirmed(owner), token, EraseEpochKnowledge(), other)) == .ownershipUnverified)
        #expect(SyncedWriteBlock.check(environment(.confirmed(owner), token, EraseEpochKnowledge(), owner)) == nil)
    }

    // MARK: - ACC-1 2차 DEBUG 소유 주입 (테스트 계획 §3-2)

    @Test("소유 주입은 실행 인자와 시험(dev) 컨테이너가 모두 맞을 때만 켜진다")
    func ownershipInjectionNeedsArgumentAndDevContainer() {
        let dev = ContainerID(id: "iCloud.Carve.SwiftData.iCloud.dev")
        let production = ContainerID(id: "iCloud.Carve.SwiftData.iCloud")
        let argument = StoreOwnershipInjection.launchArgument

        #expect(StoreOwnershipInjection.isEnabled(containerID: dev, arguments: [argument]))
        #expect(!StoreOwnershipInjection.isEnabled(containerID: dev, arguments: []))
        #expect(!StoreOwnershipInjection.isEnabled(containerID: production, arguments: [argument]))
    }

    @Test("주입한 환경은 확인된 계정에만 소유 근거를 채우고 주입했다는 표식을 단다")
    func injectedEnvironmentMarksOwnership() async throws {
        try await withStateStore { store in
            let injected = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.identified(userRecordName: "_a")]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter(), injectsOwnership: true
            )
            await injected.start()
            let current = await injected.current()
            #expect(current.storeOwnership == scope("_a"))
            #expect(current.ownershipInjected)
            #expect(SyncedWriteBlock.check(current) == nil)

            // 로그인하지 않은 경로는 주입 빌드에서도 그대로다 — 보존만 한다.
            let signedOut = LiveDrawingEditEnvironment(
                identity: SequencedIdentityClient([.noAccount]),
                containerID: container, stateStore: store, notificationCenter: NotificationCenter(), injectsOwnership: true
            )
            await signedOut.start()
            let withoutAccount = await signedOut.current()
            #expect(withoutAccount.storeOwnership == nil)
            #expect(!withoutAccount.ownershipInjected)
        }
    }

    @Test("주입하지 않은 기본값은 확인 전 환경이다 — 서버 작업을 하지 않는다")
    func unconfiguredDefaultDoesNoServerWork() async {
        let current = await StubDrawingEditEnvironment(.unknown).current()

        #expect(current.serverWork == nil)
        #expect(current.accountBasis == .unverified(hint: nil))
        #expect(current.knowledge == nil)
    }
}
