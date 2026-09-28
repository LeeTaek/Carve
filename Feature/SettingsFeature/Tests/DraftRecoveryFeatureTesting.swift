//
//  DraftRecoveryFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「남은 필기」 — 보이지 않게 남은 초안을 세어 보이는 화면 (정책 §12-6 구현 순서 ④).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

// MARK: - 대역

/// 정해 둔 초안을 돌려주는 대역. 요약을 주지 않은 묶음은 **읽지 못하는 묶음**이다.
private struct ReaderStub: VerseDraftRecoveryReading {
    struct CannotRead: Error {}
    /// nil 이면 묶음 목록부터 읽지 못한다.
    var buckets: [AccountScope]?
    var summaries: [AccountScope: DraftBucketSummary] = [:]
    var drafts: [AccountScope: [VerseDraft]] = [:]
    var unreadable: [AccountScope: [URL]] = [:]
    /// 초안 · 파일 자리를 읽은 묶음 — 지금 계정에서 열어 보지 않는 묶음은 **읽지도 않는다**(P0-1).
    let reads = LockIsolated<[AccountScope]>([])

    func draftBuckets() async throws -> [AccountScope] {
        guard let buckets else { throw CannotRead() }
        return buckets
    }

    func draftSummary(in scope: AccountScope) async throws -> DraftBucketSummary {
        guard let summary = summaries[scope] else { throw CannotRead() }
        return summary
    }

    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] {
        reads.withValue { $0.append(scope) }
        return (drafts[scope] ?? []).filter { $0.key.title == chapter.title.rawValue && $0.key.chapter == chapter.chapter }
    }

    func unreadableDraftFiles(in scope: AccountScope) async throws -> [URL] {
        reads.withValue { $0.append(scope) }
        return unreadable[scope] ?? []
    }
}

/// 그 장을 돌려주는 저장소. `ink` 가 있으면 3절에 그 필기가 있다. `holdLoads()` 면 `release()` 까지 조회를 붙잡는다.
private final class RepositoryStub: DrawingRepository, @unchecked Sendable {
    private let ink: Data?
    private let hold = LockIsolated(false)
    private let gate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)
    /// 붙잡힌 조회가 들어왔다.
    let entered = LockIsolated(0)

    init(ink: Data? = nil) {
        self.ink = ink
    }

    func holdLoads() { hold.setValue(true) }
    func release() { gate.withValue { $0?.yield(); $0?.finish(); $0 = nil } }

    func load(chapter: BibleChapter) async throws -> DrawingChapterLoad {
        if hold.value {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            gate.setValue(continuation)
            entered.withValue { $0 += 1 }
            for await _ in stream { break }
        }
        let snapshots = ink.map {
            [VerseDrawingSnapshot(verse: 3, rowID: BibleDrawingRowID(raw: "row-3"), isPresent: true, updateDate: nil,
                                  lineData: $0, drawingVersion: 3, metadata: nil)]
        } ?? []
        return DrawingChapterLoad(snapshots: snapshots, generation: DrawingStoreGeneration(raw: 0))
    }

    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter, generation: DrawingStoreGeneration) async throws {
        Issue.record("남은 필기 화면이 저장소에 썼다")
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
        Issue.record("남은 필기 화면이 저장소에 썼다")
        return .alreadyEmpty
    }
}

/// 지운 묶음을 적어 두는 대역. **초안을 지우는 길은 이 화면에 없다** — 이 대역이 받는 것은 읽지 못한 파일뿐이다.
private final class CleanerSpy: VerseDraftUnreadableCleaning, @unchecked Sendable {
    let calls = LockIsolated<[AccountScope]>([])
    private let removed: Int

    init(removed: Int = 1) {
        self.removed = removed
    }

    func removeUnreadableDraftFiles(in scope: AccountScope) async throws -> Int {
        calls.withValue { $0.append(scope) }
        return removed
    }
}

/// 시험이 바꿀 수 있는 편집 환경. 바꾸면 구독자에게 알린다.
private final class ControlledEnvironment: DrawingEditEnvironmentClient, @unchecked Sendable {
    let environment: LockIsolated<DrawingEditEnvironment>
    private let continuations = LockIsolated<[AsyncStream<Void>.Continuation]>([])

    init(_ initial: DrawingEditEnvironment) {
        environment = LockIsolated(initial)
    }

    var subscriberCount: Int { continuations.value.count }

    func current() async -> DrawingEditEnvironment { environment.value }
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool { environment.value.serverWork == token }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuations.withValue { $0.append(continuation) }
        return stream
    }

    func change(to next: DrawingEditEnvironment) {
        environment.setValue(next)
        continuations.value.forEach { $0.yield() }
    }

    func finish() {
        continuations.value.forEach { $0.finish() }
    }
}

/// 이 파일이 막는 것:
/// - 보존 영역을 열지 못한 것을 **"남은 필기가 없어요"** 로 보이는 것(있는데 없다고 말하면 사용자가 지워도 된다고 읽는다)
/// - 한 묶음을 읽지 못해 나머지 묶음까지 보이지 않는 것
/// - 다른 계정 묶음을 지금 계정의 저장소와 견준 것처럼 보이는 것
@Suite("설정 — 남은 필기")
@MainActor
struct DraftRecoveryFeatureTesting {

    private static let accountA = AccountScope(key: "acct-a")
    private static let accountB = AccountScope(key: "acct-b")
    private static let chapter = BibleChapter(title: .genesis, chapter: 1)

    private static func environment(_ scope: AccountScope, generation: UInt64 = 1) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: generation), knowledge: EraseEpochKnowledge(),
            generation: generation
        )
    }

    private static func summary(_ scope: AccountScope, drafts: Int, bytes: Int64 = 1_024, unreadable: Int = 0) -> DraftBucketSummary {
        DraftBucketSummary(
            scope: scope, draftCount: drafts, draftBytes: bytes, unreadableCount: unreadable, unreadableBytes: unreadable == 0 ? 0 : 512,
            chapters: [chapter]
        )
    }

    private static func draft(verse: Int, account: AccountScope, savedAt: TimeInterval = 1_000) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: "session-\(account.key)", chapter: chapter, verse: verse),
            revision: 1,
            rowID: BibleDrawingRowID(raw: "row-\(verse)"),
            lineData: Data("획".utf8),
            drawingVersion: 3,
            layoutMetadataData: nil,
            base: .legacy(rowID: BibleDrawingRowID(raw: "row-\(verse)"), contentFingerprint: "vc1-옛"),
            baseFingerprint: "vc1-옛",
            account: .confirmed(AccountServerWorkToken(scope: account, generation: 1)),
            knownEpochs: [],
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: savedAt)
        )
    }

    private func makeStore(
        reader: (any VerseDraftRecoveryReading)?,
        account: AccountScope = accountA,
        cleaner: (any VerseDraftUnreadableCleaning)? = nil,
        repository: RepositoryStub = RepositoryStub(),
        environment: (any DrawingEditEnvironmentClient)? = nil
    ) -> TestStoreOf<DraftRecoveryFeature> {
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = reader
            $0.verseDraftUnreadableCleaner = cleaner
            $0.drawingRepository = repository
            $0.drawingEditEnvironment = environment ?? StubDrawingEditEnvironment(Self.environment(account))
        }
        store.exhaustivity = .off
        return store
    }

    @Test("한 묶음을 읽지 못해도 나머지 묶음은 보인다 — 읽지 못한 묶음은 0개가 아니라 「읽지 못함」 이다")
    func oneUnreadableBucketDoesNotHideTheRest() async throws {
        let broken = AccountScope(key: "acct-broken")
        let reader = ReaderStub(
            buckets: [Self.accountA, broken],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader)

        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        #expect(store.state.failure == nil)
        #expect(store.state.buckets.count == 2)
        let readable = try #require(store.state.buckets.first { $0.scope == Self.accountA })
        #expect(readable.title == "지금 계정")
        #expect(readable.comparedWithStore)
        #expect(readable.items.map(\.place) == ["창세기 1:3"])
        #expect(readable.items.first?.reason == .storeMoved)
        let unreadable = try #require(store.state.buckets.first { $0.scope == broken })
        #expect(unreadable.readFailed)
        #expect(unreadable.items.isEmpty)
    }

    @Test("보존 영역을 열지 못하면 「없어요」 가 아니라 실패로 알린다")
    func missingPreservationAreaIsReportedAsFailure() async throws {
        let store = makeStore(reader: nil)

        await store.send(.view(.onAppear))
        await store.receive(\.failed)

        #expect(store.state.buckets.isEmpty)
        #expect(store.state.failure != nil)
        #expect(store.state.isLoading == false)
    }

    @Test("묶음 목록부터 읽지 못해도 실패로 알린다 — 파일이 그대로 있다고 말한다")
    func unreadableBucketListIsReportedAsFailure() async throws {
        let store = makeStore(reader: ReaderStub(buckets: nil))

        await store.send(.view(.onAppear))
        await store.receive(\.failed)

        #expect(store.state.failure?.contains("파일은 그대로") == true)
    }

    /// 2026-09-21 후속 리뷰 P0-1 — 대조하지 않는 묶음도 잉크를 상태에 담아 미리보기를 그렸다. 화면에서 가리는 것으로는 부족하다.
    @Test("B 환경에서 A 묶음은 수 · 용량만이다 — 항목 · 잉크 · 파일 자리를 만들지 않고, 초안 파일을 읽지도 않는다")
    func otherAccountBucketCarriesCountsOnly() async throws {
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1, bytes: 2_048, unreadable: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 5, account: Self.accountA)]],
            unreadable: [Self.accountA: [URL(fileURLWithPath: "/tmp/acct-a/unreadable-1")]]
        )
        let store = makeStore(reader: reader, account: Self.accountB)

        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        let bucket = try #require(store.state.buckets.first)
        #expect(!bucket.comparedWithStore)
        #expect(bucket.title.hasPrefix("다른 계정"))
        #expect(bucket.draftCount == 1)
        #expect(bucket.draftBytes == 2_048)
        #expect(bucket.unreadableCount == 1)
        // 상세가 없다 — 잉크 · 자리 · 시각을 담은 항목도, 내보낼 파일 자리도 없다.
        #expect(bucket.items.isEmpty)
        #expect(bucket.items.allSatisfy { $0.ink == nil })
        #expect(bucket.unreadableFiles.isEmpty)
        #expect(reader.reads.value.isEmpty)
        // 분류한 적 없는 수를 "자동으로 표시되지 않는 것" 으로 부르지 않는다.
        #expect(bucket.inaccessibleCount == 1)
        #expect(store.state.hiddenCount == 0)
        #expect(store.state.unopenedCount == 1)
        let detail = DraftRecoveryCopy.bucketDetail(bucket)
        #expect(detail.contains("초안 1개"))
        #expect(!detail.contains("자동으로 표시되지 않는"))
        // 그 묶음의 파일은 이 계정에서 다루지 않는다.
        await store.send(.view(.askRemoveUnreadable(Self.accountA)))
        #expect(store.state.pendingRemoval == nil)
    }

    @Test("A 목록을 연 채 계정이 바뀌면 불러온 상세 · 비교를 비우고, 새 계정 근거로 다시 읽는다")
    func accountChangeClearsLoadedDetails() async throws {
        let environment = ControlledEnvironment(Self.environment(Self.accountA))
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader, repository: RepositoryStub(ink: Data("지금 A".utf8)), environment: environment)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)
        while environment.subscriberCount == 0 { await Task.yield() }
        let item = try #require(store.state.buckets.first?.items.first)
        #expect(item.ink != nil)
        await store.send(.view(.open(Self.accountA)))
        await store.send(.view(.compare(item)))
        await store.receive(\.currentLoaded)
        #expect(store.state.comparison?.currentInk == Data("지금 A".utf8))

        environment.change(to: Self.environment(Self.accountB, generation: 2))
        await store.receive(\.environmentChanged)

        // 바뀐 즉시 앞선 근거로 불러온 것은 모두 사라진다 — 다시 읽기를 기다리지 않는다.
        #expect(store.state.buckets.isEmpty)
        #expect(store.state.comparison == nil)
        #expect(store.state.opened == nil)
        #expect(store.state.stamp == DraftRecoveryFeature.Stamp(Self.environment(Self.accountB, generation: 2)))

        await store.receive(\.loaded)
        let bucket = try #require(store.state.buckets.first)
        #expect(!bucket.comparedWithStore)
        #expect(bucket.items.isEmpty)
        environment.finish()
        await store.finish()
    }

    @Test("이전 계정에서 시작한 응답은 버린다 — 견주기 · 조회 모두")
    func lateResponsesFromThePreviousAccountAreDropped() async throws {
        let environment = ControlledEnvironment(Self.environment(Self.accountA))
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let repository = RepositoryStub(ink: Data("A 저장소".utf8))
        let store = makeStore(reader: reader, repository: repository, environment: environment)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)
        while environment.subscriberCount == 0 { await Task.yield() }
        let stampA = try #require(store.state.stamp)
        let loadedUnderA = store.state.buckets
        let item = try #require(loadedUnderA.first?.items.first)

        // A 에서 견주기를 시작했는데 저장소를 읽는 사이 계정이 B 로 바뀐다.
        repository.holdLoads()
        await store.send(.view(.compare(item)))
        while repository.entered.value == 0 { await Task.yield() }
        environment.change(to: Self.environment(Self.accountB, generation: 2))
        await store.receive(\.environmentChanged)
        repository.release()
        await store.receive(\.loaded)
        environment.finish()
        await store.finish()
        await store.skipReceivedActions(strict: false)

        // A 저장소에서 읽은 필기는 어디에도 담기지 않았다.
        #expect(store.state.comparison == nil)
        #expect(store.state.stamp != stampA)

        // 늦게 온 A 의 응답을 그대로 넣어도 버린다.
        await store.send(.currentLoaded(itemID: item.id, stamp: stampA, ink: Data("A 저장소".utf8), updatedAt: nil))
        #expect(store.state.comparison == nil)
        let staleSequence = store.state.loadSequence - 1
        await store.send(.loaded(sequence: staleSequence, stamp: stampA, loadedUnderA))
        #expect(store.state.buckets.allSatisfy { $0.items.isEmpty })
    }

    @Test("견줄 때 그 절의 지금 필기를 읽고, 다시 누르면 접는다")
    func comparingLoadsTheCurrentInk() async throws {
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)
        let item = try #require(store.state.buckets.first?.items.first)

        await store.send(.view(.compare(item)))
        await store.receive(\.currentLoaded)

        #expect(store.state.comparison?.itemID == item.id)
        #expect(store.state.comparison?.isLoading == false)
        // 대역 저장소의 그 장은 비어 있다 — "지금 그 절에는 필기가 없다".
        #expect(store.state.comparison?.currentInk == nil)
        #expect(store.state.comparison?.failure == nil)

        await store.send(.view(.compare(item))) { $0.comparison = nil }
    }

    @Test("지우기는 묻고 받은 뒤에만 읽지 못한 파일을 지우고, 지운 뒤 다시 센다")
    func removingUnreadableFilesAsksFirst() async throws {
        let cleaner = CleanerSpy()
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1, unreadable: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader, cleaner: cleaner)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        // 먼저 묻는다 — 누른 것만으로는 아무것도 지우지 않는다.
        await store.send(.view(.askRemoveUnreadable(Self.accountA))) { $0.pendingRemoval = Self.accountA }
        #expect(cleaner.calls.value.isEmpty)

        await store.send(.view(.removeUnreadableConfirmed(Self.accountA))) { $0.pendingRemoval = nil }
        await store.receive(\.removedUnreadable)

        #expect(cleaner.calls.value == [Self.accountA])
        #expect(store.state.removalResult?.contains("1개") == true)
        // 지운 뒤 다시 센다 — 남은 것이 있으면 그대로 보여야 한다.
        await store.receive(\.loaded)
    }

    @Test("지울 길이 없으면 파일이 그대로 있다고 알린다")
    func removingWithoutCleanerIsReported() async throws {
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1, unreadable: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader, cleaner: nil)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        await store.send(.view(.removeUnreadableConfirmed(Self.accountA)))
        await store.receive(\.removedUnreadable)

        #expect(store.state.removalResult?.contains("지우지 못했어요") == true)
        await store.receive(\.loaded)
    }

    @Test("로그아웃 상태에서 이 기기 전용 묶음은 「지금 계정」 이 아니라 「로그인하지 않은 동안」 이다")
    func localOnlyBucketIsNotCalledCurrentAccountWhenSignedOut() async throws {
        // 로그아웃 상태에서는 이 기기 전용 묶음이 "지금 근거의 묶음" 이지만 계정은 없다(2026-09-21 기기 확인).
        let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
        let reader = ReaderStub(
            buckets: [.localOnly],
            summaries: [.localOnly: Self.summary(.localOnly, drafts: 1)],
            drafts: [.localOnly: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = reader
            $0.verseDraftUnreadableCleaner = nil
            $0.drawingRepository = RepositoryStub()
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(signedOut)
        }
        store.exhaustivity = .off

        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        #expect(store.state.buckets.first?.title == "로그인하지 않은 동안")
    }

    /// 목록의 기준은 "그 장을 다시 열어도 자동으로 표시되지 않는 초안" 이다(2026-09-21 후속 리뷰 확정). 열린 캔버스에 지금 겹쳐 보이는지가 아니다.
    @Test("목록이 모으는 것을 「자동으로 표시되지 않는 필사 초안」 으로 말하고, 「화면에 보이지 않는」 이라 하지 않는다")
    func copySaysNotAutomaticallyShown() {
        #expect(DraftRecoveryCopy.introduction.contains("자동으로 표시되지 않는 필사 초안"))
        #expect(DraftRecoveryCopy.totalLine(draftCount: 3, draftBytes: 0, hiddenCount: 1).hasSuffix("자동으로 표시되지 않는 것 1개"))
        for text in [DraftRecoveryCopy.introduction, DraftRecoveryCopy.nothingHidden, DraftRecoveryCopy.reasonDetail(.storeMoved)] {
            #expect(!text.contains("화면에 보이지 않"))
        }
    }

    @Test("묶음을 펼쳤다 접는다")
    func openingAndClosingABucket() async throws {
        let reader = ReaderStub(
            buckets: [Self.accountA],
            summaries: [Self.accountA: Self.summary(Self.accountA, drafts: 1)],
            drafts: [Self.accountA: [Self.draft(verse: 3, account: Self.accountA)]]
        )
        let store = makeStore(reader: reader)
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        await store.send(.view(.open(Self.accountA))) { $0.opened = Self.accountA }
        await store.send(.view(.open(Self.accountA))) { $0.opened = nil }
    }
}
