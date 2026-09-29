//
//  VerseDraftImporterTesting.swift
//  DomainTest
//
//  「확인이 필요한 필기」 — 목록 조회와 가져오기를 실제 초안 파일 · 인메모리 저장소로 잇는다 (2026-09-29).
//

@testable import Domain
import Foundation
import Testing

/// 이 파일이 막는 것:
/// - 로그인하지 않은 동안 · 참고할 계정 없이 쓴 필기가 계정 연결 뒤 **볼 수도 넣을 수도 없는 것**(수 · 용량만 보이던 것)
/// - 다른 계정을 참고하던 필기를 지금 계정 화면에 담거나 가져오게 두는 것(P0-1)
/// - 넣기 직전에 환경 · 초안 · 지금 필기가 바뀌었는데도 쓰는 것, 지웠던 절에 묻지 않고 넣는 것
/// - 가져온 뒤 목록에 그대로 남거나, 그 절을 이어 고치면 다시 오르는 것
/// - 저장을 마친 내 예전 수정본을 확인이 필요한 것으로 알리는 것(사용자 결정 2026-09-29 — 접어 둔다)
@Suite("가져오기 — 목록과 가져오기")
struct VerseDraftImporterTesting {
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")

    // MARK: - 하네스

    private struct Harness {
        let store: RepositoryHarness
        let writer: LocalPreservationWriter
        var chapter: BibleChapter { store.chapter }
        var metadata: DrawingLayoutMetadata { store.metadata(verse: 1) }
        var query: VerseDraftRecoveryQuery { VerseDraftRecoveryQuery(reader: writer, repository: store.repository) }
        var importer: VerseDraftImporter {
            VerseDraftImporter(
                reader: writer, repository: store.repository, writer: store.repository, marker: writer,
                now: { Date(timeIntervalSince1970: 5_000) }
            )
        }

        func seed(verse: Int, ink: Data) async throws -> BibleDrawingRowID {
            let rowID = BibleDrawingRowID.issue()
            try await store.apply([.create(verse: verse, rowID: rowID, data: ink, metadata: store.metadata(verse: verse))], chapter: chapter)
            return rowID
        }

        func current(verse: Int) async throws -> VerseDrawingSnapshot? {
            try await store.load(chapter: chapter).representativesByVerse()[verse]
        }

        func draft(
            verse: Int, session: String, ink: Data?, account: VerseEditAccountBasis, savedAt: TimeInterval = 1_000,
            storeState: VerseDraftStoreState? = nil, sent: [String]? = nil
        ) -> VerseDraft {
            let blob = ink == nil ? nil : try? store.metadata(verse: verse).encodedBlob()
            return VerseDraft(
                key: VerseDraftKey(sessionID: session, chapter: chapter, verse: verse), revision: 1, rowID: BibleDrawingRowID(raw: "draft-row-\(verse)"),
                lineData: ink, drawingVersion: ink == nil ? nil : 3, layoutMetadataData: blob, base: .empty, baseFingerprint: nil,
                account: account, knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: savedAt),
                storeState: storeState, sentFingerprints: sent
            )
        }
    }

    private func withHarness(_ body: (Harness) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("importer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = LocalPreservationWriter(
            area: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        try await body(Harness(store: try RepositoryHarness(), writer: writer))
    }

    /// 지금 계정으로 소유가 확인된 환경 — 동기화 저장소에 써도 된다.
    private func owned(_ scope: AccountScope) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 1), knowledge: EraseEpochKnowledge(),
            storeOwnership: scope
        )
    }

    private func request(_ draft: VerseDraft, scope: AccountScope, expected: String?, caution: VerseDraftImportCheck.Caution? = nil,
                         revision: Int? = nil) -> VerseDraftImportRequest {
        VerseDraftImportRequest(
            key: draft.key, scope: scope, revision: revision ?? draft.revision, expectedCurrentFingerprint: expected, acknowledgedCaution: caution
        )
    }

    // MARK: - 목록

    @Test("확인된 계정에서 연결 전 필기의 묶음을 지금 저장소와 견준다 — 다른 계정을 참고하던 필기는 수만 센다")
    func inventoryOpensBeforeConnectionBuckets() async throws {
        try await withHarness { harness in
            _ = try await harness.seed(verse: 1, ink: importInk(1))
            _ = try await harness.writer.saveDraft(harness.draft(verse: 1, session: "logged-out", ink: importInk(2), account: .localOnly))
            _ = try await harness.writer.saveDraft(harness.draft(verse: 2, session: "no-hint", ink: importInk(3), account: .unverified(hint: nil)))
            _ = try await harness.writer.saveDraft(harness.draft(verse: 3, session: "hint-b", ink: importInk(4), account: .unverified(hint: accountB)))
            let environment = owned(accountA)

            let localOnly = try await harness.query.inventory(in: .localOnly, environment: environment)
            let verseOne = try await harness.current(verse: 1)
            #expect(localOnly.comparedWithStore)
            #expect(localOnly.entries.map(\.reason) == [.beforeConnection])
            // 비교의 한쪽 — 그 절의 지금 필기(지금 계정의 저장소)를 함께 든다.
            #expect(localOnly.entries.first?.current?.contentFingerprint == verseOne?.contentFingerprint)
            #expect(localOnly.inaccessibleCount == 0)

            let unverified = try await harness.query.inventory(in: .unverified, environment: environment)
            #expect(unverified.comparedWithStore)
            #expect(unverified.entries.map(\.draft.key.verse) == [2])
            #expect(unverified.entries.map(\.reason) == [.beforeConnection])
            // 다른 계정을 참고하던 필기는 상세 없이 수만 센다(P0-1).
            #expect(unverified.inaccessibleCount == 1)

            #expect(await harness.query.beforeConnectionCount(environment: environment) == 2)
            // 계정이 확인되지 않았으면 안내할 것이 없다 — 가져올 곳이 없다.
            let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
            #expect(await harness.query.beforeConnectionCount(environment: signedOut) == 0)
        }
    }

    @Test("저장을 마친 뒤 이어 고친 내 예전 수정본은 「예전에 저장한 필기」 로 따로 오른다 — 확인이 필요한 것에 들지 않는다")
    func savedEarlierRevisionIsListedApart() async throws {
        try await withHarness { harness in
            let row = try await harness.seed(verse: 1, ink: importInk(2))
            let sentContent = try #require(try await harness.current(verse: 1)?.contentFingerprint)
            var earlier = harness.draft(verse: 1, session: "earlier", ink: importInk(2), account: .confirmed(
                AccountServerWorkToken(scope: accountA, generation: 1)
            ), storeState: .stored, sent: [sentContent])
            earlier.rowID = row
            _ = try await harness.writer.saveDraft(earlier)
            // 그 뒤 그 절을 이어 고쳤다(다음 세션의 저장).
            try await harness.store.apply([.replace(verse: 1, rowID: row, data: importInk(3), metadata: harness.metadata)], chapter: harness.chapter)

            let inventory = try await harness.query.inventory(in: accountA, environment: owned(accountA))
            #expect(inventory.entries.map(\.reason) == [.savedEarlier])
            #expect(inventory.entries.allSatisfy { !$0.reason.needsConfirmation })
        }
    }

    // MARK: - 가져오기

    @Test("연결 전 필기를 가져오면 그 절의 새 대표가 되고 초안에 기록이 남는다 — 목록에서 빠지고, 그 절을 이어 고쳐도 다시 오르지 않는다")
    func importsABeforeConnectionDraft() async throws {
        try await withHarness { harness in
            let previous = try await harness.seed(verse: 1, ink: importInk(1))
            let local = harness.draft(verse: 1, session: "logged-out", ink: importInk(2), account: .localOnly)
            _ = try await harness.writer.saveDraft(local)
            let environment = owned(accountA)
            let listed = try #require(try await harness.query.inventory(in: .localOnly, environment: environment).entries.first)

            let result = try await harness.importer.importDraft(
                request(local, scope: .localOnly, expected: listed.current?.contentFingerprint), environment: environment
            )

            #expect(result == .imported(previousKept: true, recorded: true))
            let now = try #require(try await harness.current(verse: 1))
            #expect(now.lineData == importInk(2))
            #expect(now.rowID != previous)
            // 지금까지의 필기는 지우지 않았다 — 대표에서 내려와 이전 필사 기록으로 남는다.
            let history = try await harness.store.load(chapter: harness.chapter).first { $0.rowID == previous }
            #expect(history?.lineData == importInk(1))
            #expect(history?.isPresent == false)
            // 초안은 지우지 않고 무엇을 · 어느 계정의 어느 행으로 · 언제 가져왔는지 남긴다.
            let stored = try await harness.writer.drafts(in: .localOnly)
            #expect(stored.count == 1)
            #expect(stored.first?.imported == VerseDraftImport(
                rowID: now.rowID, contentFingerprint: local.contentFingerprint, account: accountA, importedAt: Date(timeIntervalSince1970: 5_000)
            ))
            // 목록에서 빠진다.
            #expect(try await harness.query.inventory(in: .localOnly, environment: environment).entries.isEmpty)
            #expect(await harness.query.beforeConnectionCount(environment: environment) == 0)

            // 그 절을 이어 고쳐도(편집 화면의 저장) 가져온 초안은 다시 오르지 않는다.
            try await harness.store.apply([.replace(verse: 1, rowID: now.rowID, data: importInk(3), metadata: harness.metadata)], chapter: harness.chapter)
            #expect(try await harness.query.inventory(in: .localOnly, environment: environment).entries.isEmpty)
        }
    }

    @Test("넣기 직전에 다시 본다 — 쓸 수 없는 환경 · 다른 계정을 참고하던 필기 · 바뀐 초안 · 바뀐 지금 필기면 쓰지 않는다")
    func importRechecksEverythingBeforeWriting() async throws {
        try await withHarness { harness in
            let previous = try await harness.seed(verse: 1, ink: importInk(1))
            let expected = try await harness.current(verse: 1)?.contentFingerprint
            let local = harness.draft(verse: 1, session: "logged-out", ink: importInk(2), account: .localOnly)
            let otherHint = harness.draft(verse: 1, session: "hint-b", ink: importInk(3), account: .unverified(hint: accountB))
            _ = try await harness.writer.saveDraft(local)
            _ = try await harness.writer.saveDraft(otherHint)

            var unowned = owned(accountA)
            unowned.storeOwnership = nil
            #expect(try await harness.importer.importDraft(request(local, scope: .localOnly, expected: expected), environment: unowned)
                == .blocked(.ownershipUnverified))
            var held = owned(accountA)
            held.connectionHeld = true
            #expect(try await harness.importer.importDraft(request(local, scope: .localOnly, expected: expected), environment: held)
                == .blocked(.connectionHeld))
            #expect(try await harness.importer.importDraft(request(otherHint, scope: .unverified, expected: expected), environment: owned(accountA))
                == .blocked(.verseFromOtherSession))
            #expect(try await harness.importer.importDraft(request(local, scope: .localOnly, expected: expected, revision: 2), environment: owned(accountA))
                == .draftChanged)
            // 사용자는 빈 절이라고 보고 골랐다 — 그 사이 필기가 들어왔다.
            #expect(try await harness.importer.importDraft(request(local, scope: .localOnly, expected: nil), environment: owned(accountA))
                == .currentChanged)

            // 아무것도 쓰지 않았다 — 저장소도 초안도 그대로다.
            #expect(try await harness.store.rows(verse: 1).map(\.rowKey) == [previous.raw])
            #expect(try await harness.writer.drafts(in: .localOnly).first?.imported == nil)
        }
    }

    @Test("이 필기를 쓴 뒤 그 절이 비워졌으면 사용자가 그 주의를 확인한 뒤에만 넣는다")
    func clearedVerseNeedsAcknowledgement() async throws {
        try await withHarness { harness in
            let cleared = try await harness.seed(verse: 1, ink: importInk(1))
            try await harness.store.apply([.clear(verse: 1, rowID: cleared)], chapter: harness.chapter)
            let local = harness.draft(verse: 1, session: "logged-out", ink: importInk(2), account: .localOnly, savedAt: 1_000)
            _ = try await harness.writer.saveDraft(local)
            let environment = owned(accountA)

            #expect(try await harness.importer.importDraft(request(local, scope: .localOnly, expected: nil), environment: environment)
                == .cautionRequired(.verseClearedAfterDraft))
            #expect(try await harness.store.rows(verse: 1).count == 1)

            let result = try await harness.importer.importDraft(
                request(local, scope: .localOnly, expected: nil, caution: .verseClearedAfterDraft), environment: environment
            )
            #expect(result == .imported(previousKept: false, recorded: true))
            #expect(try await harness.current(verse: 1)?.lineData == importInk(2))
        }
    }

    @Test("좌표 정보를 읽지 못한 필기는 목록에 표시 실패로 오르고 넣지 않는다")
    func undisplayableDraftIsNotImported() async throws {
        try await withHarness { harness in
            var lost = harness.draft(verse: 1, session: "lost", ink: importInk(2), account: .localOnly)
            lost.layoutMetadataData = nil
            _ = try await harness.writer.saveDraft(lost)
            let environment = owned(accountA)

            let entries = try await harness.query.inventory(in: .localOnly, environment: environment).entries
            #expect(entries.map(\.reason) == [.undisplayable])
            #expect(await harness.query.beforeConnectionCount(environment: environment) == 0)
            #expect(try await harness.importer.importDraft(request(lost, scope: .localOnly, expected: nil), environment: environment) == .unavailable)
            #expect(try await harness.store.rows(verse: 1).isEmpty)
        }
    }
}
