//
//  VerseDraftRecoveryInventoryTesting.swift
//  DomainTest
//
//  복구 화면(④)이 "보이지 않게 남은 것" 을 찾는 조회 — 초안이 남은 장만 저장소와 대조한다 (정책 §12-6 구현 순서 ②-④).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 편집 화면에 **보이는** 초안을 "보이지 않게 남은 것" 으로 또 알리는 것(사용자가 판단할 것과 아닌 것이 섞인다)
/// - 이미 저장소에 들어간 초안(`settled`)을 남아 있다는 이유만으로 안내하는 것
/// - 다른 계정 묶음의 초안을 **지금 계정의 저장소**와 견주어 엉뚱하게 분류하는 것(그 계정으로 돌아왔을 때 연다)
/// - 한 장을 읽지 못해 목록 전체가 막히는 것 — 나머지 장의 초안까지 보이지 않는다
///
/// 판정 자체는 `VerseDraftRecoveryRuleTesting` 이 표로 다룬다. 여기서는 **실제 초안 파일**을 두고, 화면이 보이는 것과 목록이 알리는 것이
/// 서로 엇갈리지 않는지를 본다.
@Suite("초안 복구 조회 — 보이지 않게 남은 것")
struct VerseDraftRecoveryInventoryTesting {

    private let genesis1 = BibleChapter(title: .genesis, chapter: 1)
    private let genesis2 = BibleChapter(title: .genesis, chapter: 2)
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")

    // MARK: - 대역

    /// 장 조회만 답하는 저장소. 복구 화면의 조회는 **쓰지 않는다** — 쓰기가 오면 시험이 깨진다.
    private actor StubRepository: DrawingRepository {
        private let chapters: [BibleChapter: [VerseDrawingSnapshot]]
        private(set) var loadCount = 0

        init(_ chapters: [BibleChapter: [VerseDrawingSnapshot]]) {
            self.chapters = chapters
        }

        func load(chapter: BibleChapter) async throws -> DrawingChapterLoad {
            loadCount += 1
            return DrawingChapterLoad(snapshots: chapters[chapter] ?? [], generation: DrawingStoreGeneration(raw: 0))
        }

        func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter, generation: DrawingStoreGeneration) async throws {
            Issue.record("복구 화면의 조회가 저장소에 썼다")
        }

        func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
            Issue.record("복구 화면의 조회가 저장소에 썼다")
            return .alreadyEmpty
        }
    }

    private struct Areas {
        let preservation: PreservationArea
        let eraseState: EraseStateArea
    }

    private func withWriter(_ body: (LocalPreservationWriter, Areas) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("draft-inventory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let areas = Areas(
            preservation: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        try await body(LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState), areas)
    }

    // MARK: - 표본

    private func environment(_ scope: AccountScope) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 1), knowledge: EraseEpochKnowledge()
        )
    }

    /// 저장소의 한 행. 초안과 **같은 규칙**으로 지문이 만들어진다(좌표 정보 없음).
    private func row(verse: Int, rowID: String, ink: String?, updatedAt: TimeInterval = 500) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowID), isPresent: true, updateDate: Date(timeIntervalSince1970: updatedAt),
            lineData: ink.map { Data($0.utf8) }, drawingVersion: ink == nil ? nil : 3, metadata: nil
        )
    }

    private func fingerprint(_ ink: String) -> String {
        VerseContentFingerprint.make(lineData: Data(ink.utf8), drawingVersion: 3, layoutMetadataBlob: nil)
    }

    private func draft(
        chapter: BibleChapter? = nil,
        verse: Int = 1,
        session: String = "s1",
        rowID: String? = nil,
        ink: String?,
        baseInk: String?,
        account: VerseEditAccountBasis? = nil,
        savedAt: TimeInterval = 1_000,
        storeState: VerseDraftStoreState? = nil,
        sentFingerprints: [String]? = nil
    ) -> VerseDraft {
        let chapter = chapter ?? genesis1
        let row = BibleDrawingRowID(raw: rowID ?? "row-\(verse)")
        return VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: chapter, verse: verse),
            revision: 1,
            rowID: row,
            lineData: ink.map { Data($0.utf8) },
            drawingVersion: ink == nil ? nil : 3,
            layoutMetadataData: nil,
            base: baseInk.map { .legacy(rowID: row, contentFingerprint: fingerprint($0)) } ?? .empty,
            baseFingerprint: baseInk.map { fingerprint($0) },
            account: account ?? .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)),
            knownEpochs: [],
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: savedAt),
            storeState: storeState,
            sentFingerprints: sentFingerprints
        )
    }

    // MARK: - 보이는 것은 알리지 않는다

    @Test("화면에 보이는 초안과 이미 저장소에 든 초안은 목록에 없다 — 밀린 초안과 기준이 달라진 초안만 오른다")
    func inventoryListsOnlyWhatTheScreenDoesNotShow() async throws {
        try await withWriter { writer, _ in
            // 1절: 같은 절에 두 세션의 초안. 늦게 쓴 쪽이 화면에 오르고 앞선 쪽은 밀린다.
            _ = try await writer.saveDraft(draft(verse: 1, session: "older", ink: "가", baseInk: "옛", savedAt: 1_000))
            _ = try await writer.saveDraft(draft(verse: 1, session: "newer", ink: "나", baseInk: "옛", savedAt: 2_000))
            // 2절: 초안의 내용이 이미 저장소의 그 절 내용이다 — 역할이 끝났다.
            _ = try await writer.saveDraft(draft(verse: 2, session: "older", ink: "들어감", baseInk: "옛2", savedAt: 1_500))
            // 3절: 기준이 지금 저장소 내용과 다르다 — 그 사이 다른 내용이 들어왔다.
            _ = try await writer.saveDraft(draft(verse: 3, session: "older", ink: "다", baseInk: "옛3", savedAt: 1_800))

            let repository = StubRepository([genesis1: [
                row(verse: 1, rowID: "row-1", ink: "옛"),
                row(verse: 2, rowID: "row-2", ink: "들어감"),
                row(verse: 3, rowID: "row-3", ink: "남이 넣음")
            ]])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventory(in: accountA, environment: environment(accountA))

            #expect(inventory.comparedWithStore)
            #expect(inventory.unreadChapters.isEmpty)
            #expect(inventory.summary.draftCount == 4)
            // 3절(1_800) → 1절의 밀린 초안(1_000). 보이는 초안(1절 newer)과 역할이 끝난 초안(2절)은 없다.
            #expect(inventory.entries.map { ($0.draft.key.verse, $0.reason) }.map { "\($0.0):\($0.1.rawValue)" }
                == ["3:storeMoved", "1:newerDraftShown"])
            // 비교의 한쪽 — 그 절의 지금 필기를 함께 든다.
            let pushed = try #require(inventory.entries.first { $0.draft.key.verse == 1 })
            #expect(pushed.current?.contentFingerprint == fingerprint("옛"))
            #expect(pushed.current?.rowID == BibleDrawingRowID(raw: "row-1"))
            #expect(pushed.current?.updatedAt == Date(timeIntervalSince1970: 500))
            // 초안이 남은 장만 읽는다 — 이 묶음에는 창세기 1장뿐이다.
            #expect(await repository.loadCount == 1)
        }
    }

    // MARK: - 사용자가 판단해야 하는 것

    @Test("저장 완료가 불확실한 초안과 되살릴 수 있는 초안을 따로 알린다")
    func inventoryTellsUncertainAndRecoverableApart() async throws {
        try await withWriter { writer, _ in
            // 1절: 보내던 중에 끝났고 그 행이 그 뒤로 바뀌었다 — 들어갔는지 가릴 수 없다.
            _ = try await writer.saveDraft(draft(verse: 1, ink: "보내던 것", baseInk: "옛", storeState: .sending))
            // 2절: 넣은 것은 들어갔는데 그 행이 **내가 넣었던 내용**으로 돌아왔다 — 그 뒤 편집은 이 초안에만 있다(F29).
            _ = try await writer.saveDraft(draft(
                verse: 2, ink: "그 뒤 편집", baseInk: "옛2", storeState: .stored, sentFingerprints: [fingerprint("내가 넣은 것")]
            ))

            let repository = StubRepository([genesis1: [
                row(verse: 1, rowID: "row-1", ink: "남이 넣음"),
                row(verse: 2, rowID: "row-2", ink: "내가 넣은 것")
            ]])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventory(in: accountA, environment: environment(accountA))

            let reasons = Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.draft.key.verse, $0.reason) })
            #expect(reasons == [1: .uncertain, 2: .recoverable])
            // 되살릴 후보는 지금 필기와 견줄 수 있어야 한다.
            #expect(inventory.entries.first { $0.draft.key.verse == 2 }?.current?.contentFingerprint == fingerprint("내가 넣은 것"))
        }
    }

    // MARK: - 다른 계정 묶음

    @Test("다른 계정 묶음은 저장소를 읽지 않고 세어 보이기만 한다 — 지금 저장소는 그 계정의 내용이 아니다")
    func otherAccountBucketIsNotComparedWithTheStore() async throws {
        try await withWriter { writer, _ in
            let other = VerseEditAccountBasis.confirmed(AccountServerWorkToken(scope: accountB, generation: 1))
            _ = try await writer.saveDraft(draft(verse: 1, ink: "가", baseInk: "옛", account: other))
            _ = try await writer.saveDraft(draft(chapter: genesis2, verse: 5, ink: "나", baseInk: "옛", account: other))

            let repository = StubRepository([:])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventory(in: accountB, environment: environment(accountA))

            #expect(!inventory.comparedWithStore)
            #expect(inventory.entries.count == 2)
            #expect(inventory.entries.allSatisfy { $0.reason == .otherBasis && $0.current == nil })
            #expect(await repository.loadCount == 0)
        }
    }

    @Test("확인 전 묶음에서 힌트가 다른 초안은 다른 근거로 오르고, 힌트가 같아 화면에 오르는 초안은 목록에 없다")
    func unverifiedDraftsFollowTheSameHintRuleAsTheScreen() async throws {
        try await withWriter { writer, _ in
            _ = try await writer.saveDraft(draft(verse: 1, session: "hint-a", ink: "가", baseInk: "옛", account: .unverified(hint: accountA)))
            _ = try await writer.saveDraft(draft(verse: 2, session: "hint-b", ink: "나", baseInk: "옛2", account: .unverified(hint: accountB)))

            let repository = StubRepository([genesis1: [
                row(verse: 1, rowID: "row-1", ink: "옛"),
                row(verse: 2, rowID: "row-2", ink: "옛2")
            ]])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventory(in: .unverified, environment: environment(accountA))

            #expect(inventory.comparedWithStore)
            // 1절은 힌트가 지금 계정과 같아 편집 화면에 오른다 — 목록은 그것을 또 알리지 않는다.
            #expect(inventory.entries.map(\.draft.key.verse) == [2])
            #expect(inventory.entries.first?.reason == .otherBasis)
            #expect(inventory.entries.first?.current == nil)
        }
    }

    // MARK: - 읽지 못하는 장

    @Test("한 장을 읽지 못해도 나머지 장은 알린다 — 그 장은 따로 알리고 파일은 남는다")
    func oneUnreadableChapterDoesNotBlockTheList() async throws {
        try await withWriter { writer, areas in
            _ = try await writer.saveDraft(draft(verse: 1, ink: "가", baseInk: "옛"))
            let broken = draft(chapter: genesis2, verse: 7, ink: "나", baseInk: "옛")
            _ = try await writer.saveDraft(broken)
            let url = areas.preservation.draftsDirectory
                .appendingPathComponent(accountA.key, isDirectory: true)
                .appendingPathComponent(broken.key.sessionID, isDirectory: true)
                .appendingPathComponent(broken.key.fileName)
            try Data("{ 잘린".utf8).write(to: url)

            let repository = StubRepository([genesis1: [row(verse: 1, rowID: "row-1", ink: "남이 넣음")]])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventory(in: accountA, environment: environment(accountA))

            #expect(inventory.unreadChapters == [genesis2])
            #expect(inventory.entries.map(\.draft.key.verse) == [1])
            // 파일은 그대로다 — 개수 · 용량은 깨진 것까지 센다.
            #expect(inventory.summary.draftCount == 2)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
