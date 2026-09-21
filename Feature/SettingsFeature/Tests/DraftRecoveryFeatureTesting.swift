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

    /// 정해 둔 초안을 돌려주는 대역. 요약을 주지 않은 묶음은 **읽지 못하는 묶음**이다.
    private struct ReaderStub: VerseDraftRecoveryReading {
        struct CannotRead: Error {}
        /// nil 이면 묶음 목록부터 읽지 못한다.
        var buckets: [AccountScope]?
        var summaries: [AccountScope: DraftBucketSummary] = [:]
        var drafts: [AccountScope: [VerseDraft]] = [:]

        func draftBuckets() async throws -> [AccountScope] {
            guard let buckets else { throw CannotRead() }
            return buckets
        }

        func draftSummary(in scope: AccountScope) async throws -> DraftBucketSummary {
            guard let summary = summaries[scope] else { throw CannotRead() }
            return summary
        }

        func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] {
            (drafts[scope] ?? []).filter { $0.key.title == chapter.title.rawValue && $0.key.chapter == chapter.chapter }
        }

        func unreadableDraftFiles(in scope: AccountScope) async throws -> [URL] { [] }
    }

    /// 빈 장을 돌려주는 저장소.
    private struct RepositoryStub: DrawingRepository {
        func load(chapter: BibleChapter) async throws -> DrawingChapterLoad {
            DrawingChapterLoad(snapshots: [], generation: DrawingStoreGeneration(raw: 0))
        }

        func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter, generation: DrawingStoreGeneration) async throws {
            Issue.record("남은 필기 화면이 저장소에 썼다")
        }

        func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
            Issue.record("남은 필기 화면이 저장소에 썼다")
            return .alreadyEmpty
        }
    }

    private static func environment(_ scope: AccountScope) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 1), knowledge: EraseEpochKnowledge()
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

    private func makeStore(reader: (any VerseDraftRecoveryReading)?, account: AccountScope = accountA) -> TestStoreOf<DraftRecoveryFeature> {
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = reader
            $0.drawingRepository = RepositoryStub()
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(Self.environment(account))
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

    @Test("다른 계정 묶음은 견주지 않았다고 표시하고 다른 근거로 센다")
    func otherAccountBucketIsMarkedAsNotCompared() async throws {
        let reader = ReaderStub(
            buckets: [Self.accountB],
            summaries: [Self.accountB: Self.summary(Self.accountB, drafts: 1, unreadable: 1)],
            drafts: [Self.accountB: [Self.draft(verse: 5, account: Self.accountB)]]
        )
        let store = makeStore(reader: reader)

        await store.send(.view(.onAppear))
        await store.receive(\.loaded)

        let bucket = try #require(store.state.buckets.first)
        #expect(!bucket.comparedWithStore)
        #expect(bucket.title.hasPrefix("다른 계정"))
        #expect(bucket.unreadableCount == 1)
        #expect(bucket.items.map(\.reason) == [.otherBasis])
        // 견주지 않았으므로 "지금 그 절" 을 말하지 않는다.
        #expect(bucket.items.first?.currentIsEmpty == nil)
        #expect(bucket.items.first?.provenance == "다른 계정에서 씀")
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
