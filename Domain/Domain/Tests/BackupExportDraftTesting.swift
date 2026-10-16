//
//  BackupExportDraftTesting.swift
//  DomainTest
//
//  필사 백업 내보내기 — 저장소에 반영되지 않은 초안을 「확인이 필요한 필기」 와 같은 규칙으로 담는다 (설계 docs/backup-import-design.md §3-4, 결정 2).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - iCloud 에 로그인하지 않은 기기의 2.0 필기(초안 `acct-local` 에만 있다)가 백업에서 통째로 빠지는 것
/// - 화면에 겹치던 초안(shown)이 있는데 그 절의 행을 현재로 담아, 불러온 기기에서 다른 필기가 보이는 것
/// - 이미 저장소에 든 초안(settled)을 또 담는 것
/// - **다른 계정의 필기**(다른 계정 묶음 · 다른 계정을 참고하던 확인 전 초안)를 지금 계정의 파일에 담는 것(P0-1), 파일에 계정 해시를 남기는 것
/// - 초안을 읽지 못한 장을 조용히 빼고 성공으로 끝내는 것
@Suite("백업 내보내기 — 초안")
struct BackupExportDraftTesting {

    private let localSession = VerseEditAccountBasis.localOnly

    @Test("로그인하지 않은 기기 — acct-local 초안을 담고, 화면에 겹치던 초안은 현재 · 그 절의 행은 현재가 아니다")
    func signedOutLocalDraftsAreBackedUp() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 2절 행 X(대표) · 4절 행 Z(대표). 로그인하지 않은 동안 쓴 초안 —
        //   2절: X 를 보고 고친 Y(기준이 지금 내용 그대로 → 화면에 겹친다), 3절: 빈 절에 쓴 W(겹친다),
        //   4절: 다른 내용을 보고 쓴 V(기준이 지금 Z 와 다르다 → 보이지 않고 남는다).
        let inkX = BackupExportSample.ink("X")
        try harness.seed([
            BackupExportRowSeed(verse: 2, rowUUID: "ROW-X", lineData: inkX, layoutMetadataData: BackupExportSample.metadata),
            BackupExportRowSeed(verse: 4, rowUUID: "ROW-Z", lineData: BackupExportSample.ink("Z"), layoutMetadataData: BackupExportSample.metadata)
        ])
        let shownOverRow = BackupExportSample.draft(
            verse: 2, ink: BackupExportSample.ink("Y"),
            base: .legacy(rowID: BibleDrawingRowID(raw: "ROW-X"), contentFingerprint: BackupExportSample.fingerprint(inkX)), account: localSession
        )
        let shownOnEmpty = BackupExportSample.draft(verse: 3, ink: BackupExportSample.ink("W"), account: localSession, revision: 7)
        let kept = BackupExportSample.draft(
            verse: 4, ink: BackupExportSample.ink("V"),
            base: .legacy(rowID: BibleDrawingRowID(raw: "ROW-Z"), contentFingerprint: BackupExportSample.fingerprint(BackupExportSample.ink("옛 Z"))),
            account: localSession
        )
        try await harness.save([shownOverRow, shownOnEmpty, kept])

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then: 초안 셋 모두 담기고, 겹치던 둘만 현재다.
        #expect(payload.manifest.counts.rows == 2 && payload.manifest.counts.drafts == 3)
        let verse2 = try #require(payload.drafts(verse: 2).first)
        let verse3 = try #require(payload.drafts(verse: 3).first)
        let verse4 = try #require(payload.drafts(verse: 4).first)
        #expect(verse2.isCurrent && verse3.isCurrent)
        #expect(!verse4.isCurrent)
        // 겹치던 초안이 있는 절의 행은 현재가 아니고, 보이지 않던 초안의 절은 행이 그대로 현재다.
        #expect(payload.row("ROW-X")?.isCurrent == false)
        #expect(payload.row("ROW-Z")?.isCurrent == true)

        // 초안 항목의 모양 — 만든 시각 없음 · 남긴 시각 · 묶음 종류 · revision · 원본 바이트.
        let fingerprint = BackupExportSample.fingerprint(BackupExportSample.ink("W"))
        let sourceKey = BackupItemID.draftSourceKey(
            draftScope: "local", sessionID: "session-1", translation: "NKRV", title: BibleTitle.genesis.rawValue, chapter: 1, verse: 3, revision: 7,
            notebook: nil
        )
        #expect(verse3.id == BackupItemID.make(kind: .draft, sourceKey: sourceKey, fingerprint: fingerprint))
        #expect(verse3.kind == .draft)
        #expect(verse3.verse == BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 3))
        #expect(verse3.drawingVersion == 3)
        #expect(verse3.fingerprint == fingerprint)
        #expect(verse3.createdAt == nil)
        #expect(verse3.updatedAt == BackupExportSample.draftSavedAt)
        #expect(verse3.source == BackupItemSource(titleName: BibleTitle.genesis.rawValue, draftScope: "local", draftRevision: 7))
        #expect(payload.bytes(verse3.inkBlob) == BackupExportSample.ink("W"))
        #expect(payload.bytes(verse3.metadataBlob) == BackupExportSample.metadata)
    }

    @Test("이미 저장소에 든 초안(settled)은 담지 않는다")
    func settledDraftIsLeftOut() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 1절 대표가 초안과 같은 내용이다 — 역할이 끝난 초안.
        let ink = BackupExportSample.ink("들어감")
        try harness.seed([BackupExportRowSeed(verse: 1, rowUUID: "ROW-1", lineData: ink, layoutMetadataData: BackupExportSample.metadata)])
        try await harness.save([BackupExportSample.draft(verse: 1, ink: ink, account: localSession)])

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then
        let rowsOnly = payload.items.allSatisfy { $0.kind == .row }
        #expect(rowsOnly)
        #expect(payload.row("ROW-1")?.isCurrent == true)
        #expect(result.counts == BackupCounts(rows: 1, drafts: 0, blobs: 2))
    }

    @Test("확인된 계정 — 그 계정 묶음 · 연결 전 필기를 담고, 다른 계정 묶음과 다른 계정을 참고하던 확인 전 초안은 담지 않는다")
    func otherAccountDraftsAreNeverBackedUp() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        let accountA = BackupExportSample.accountA
        let accountB = BackupExportSample.accountB
        let tokenA = AccountServerWorkToken(scope: accountA, generation: 1)
        let tokenB = AccountServerWorkToken(scope: accountB, generation: 1)
        // Given: 장 하나에 다섯 묶음의 초안.
        try await harness.save([
            // 1절: 지금 계정 A 의 묶음 — 화면에 겹친다.
            BackupExportSample.draft(verse: 1, ink: BackupExportSample.ink("A"), account: .confirmed(tokenA), storeOwnership: accountA),
            // 2절: 다른 계정 B 의 묶음 — 열지 않는다.
            BackupExportSample.draft(verse: 2, ink: BackupExportSample.ink("B"), account: .confirmed(tokenB), storeOwnership: accountB),
            // 3절: B 를 참고하던 확인 전 초안 — 다른 사람의 필기일 수 있다.
            BackupExportSample.draft(verse: 3, ink: BackupExportSample.ink("확인 전 B"), account: .unverified(hint: accountB)),
            // 4절: 참고할 계정 없이 확인 전에 쓴 초안 — 연결 전 필기.
            BackupExportSample.draft(verse: 4, ink: BackupExportSample.ink("확인 전"), account: .unverified(hint: nil)),
            // 5절: 로그인하지 않은 동안 쓴 초안 — 연결 전 필기.
            BackupExportSample.draft(verse: 5, ink: BackupExportSample.ink("로컬"), account: .localOnly)
        ])

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.confirmed(accountA)))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try harness.open(result)

        // Then: A 의 묶음은 현재로, 연결 전 필기 둘은 현재가 아니게 담긴다. 2 · 3절은 없다.
        let drafts = payload.items.filter { $0.kind == .draft }
        #expect(drafts.map(\.verse.verse).sorted() == [1, 4, 5])
        #expect(payload.drafts(verse: 1).first?.isCurrent == true)
        #expect(payload.drafts(verse: 1).first?.source.draftScope == "account")
        #expect(payload.drafts(verse: 4).first?.isCurrent == false)
        #expect(payload.drafts(verse: 4).first?.source.draftScope == "unverified")
        #expect(payload.drafts(verse: 5).first?.isCurrent == false)
        #expect(payload.drafts(verse: 5).first?.source.draftScope == "local")
        // 파일 어디에도 계정 해시가 없다.
        let unpacked = payload.blobDirectory.deletingLastPathComponent()
        for name in [BackupFormat.manifestFileName, BackupFormat.itemsFileName] {
            let text = try String(contentsOf: unpacked.appendingPathComponent(name), encoding: .utf8)
            #expect(!text.contains(accountA.key) && !text.contains(accountB.key) && !text.contains("acct-"))
        }
    }

    @Test("초안 파일을 읽지 못한 장이 있으면 그 장을 빼지 않고 실패한다 — 작업 폴더를 남기지 않는다")
    func unreadableDraftFailsTheExport() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        // Given: 행 하나와, acct-local 에 읽을 수 없는 초안 파일 하나(같은 장).
        try harness.seed([
            BackupExportRowSeed(verse: 1, rowUUID: "ROW-1", lineData: BackupExportSample.ink("1"), layoutMetadataData: BackupExportSample.metadata)
        ])
        let key = VerseDraftKey(sessionID: "broken-session", page: BackupExportSample.genesis1.inDefaultNotebook, verse: 9)
        let session = harness.preservation.draftsDirectory
            .appendingPathComponent(AccountScope.localOnly.key, isDirectory: true)
            .appendingPathComponent(key.sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try Data("깨진 초안".utf8).write(to: session.appendingPathComponent(key.fileName))

        // When · Then
        await #expect(throws: BackupExportError.draftsUnreadable) {
            _ = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
                .export(password: BackupExportSample.password) { _ in }
        }
        #expect(harness.leftovers().isEmpty)
    }
}
