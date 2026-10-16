//
//  BackupNotebookRoundTripTesting.swift
//  DomainTest
//
//  필사 백업 형식 2 — 필사책(2.2 「회차별 필사책」)의 행 · 정보를 담고 되살리며 필사책끼리 섞지 않는다
//  (설계 docs/notebook-design.md 백업 줄 · 혼재 버전 규칙 ⑤ · ⑥).
//

import Foundation
import SwiftData
import Testing

@testable import Domain

/// 이 스위트가 막는 것:
/// - 다른 필사책 행(`nb_<토큰>~` 접두)이 내보내기에서 빠지거나, 불러오기가 그 행을 기본 필사책 행으로 합치는 것
/// - 같은 내용이라도 필사책이 다르면 다른 절인데 `skipSame` 으로 버리는 것
/// - 필사책 이름 · 상태 · 예약 필드를 내보내기 · 불러오기에서 잃는 것
/// - 형식 1 파일(2.1)을 거부하거나 기본 필사책 밖에 넣는 것, 형식 3(뒤 버전)을 읽는 것
/// - 알 수 없는 필사책 토큰의 항목을 기본 필사책에 넣거나, 그 항목 때문에 파일 전체를 거부하는 것
/// - 다른 필사책의 초안이 내보내기에서 빠지거나, 같은 세션 · 절 · revision · 내용의 두 필사책 초안 id 가 겹쳐 내보낸 파일이 깨지는 것
@Suite("필사 백업 — 필사책(형식 2)")
struct BackupNotebookRoundTripTesting {
    private typealias Sample = BackupRestoreSample
    private typealias Fixture = BackupNotebookFixture

    // MARK: - 왕복

    @Test("왕복 — 기본 · A · B 필사책의 행과 정보가 필사책 · titleName · 이름 그대로 돌아오고, 같은 내용이라도 필사책끼리 섞이지 않는다")
    func roundTripKeepsNotebooksApart() async throws {
        // Given: 내보내는 기기 — 기본 1절(잉크 same), A 1절(개역개정) · A KJV 1절, B 1절(기본과 같은 잉크) · B 출애굽기 3장 2절.
        let source = try BackupExportHarness()
        defer { source.remove() }
        var defaultRow = BackupExportRowSeed(
            verse: 1, rowUUID: "D-1", creationDate: Sample.sep(1), updateDate: Sample.sep(2),
            lineData: Sample.ink("same"), layoutMetadataData: Sample.metadata
        )
        defaultRow.notebook = .default
        var rowA = BackupExportRowSeed(
            verse: 1, rowUUID: "A-1", creationDate: Sample.sep(3), updateDate: Sample.sep(4),
            lineData: Sample.ink("a-1"), layoutMetadataData: Sample.metadata
        )
        rowA.notebook = Fixture.notebookA
        var rowAKJV = BackupExportRowSeed(
            chapter: Fixture.kjvGenesis1, verse: 1, rowUUID: "A-KJV-1", translation: nil, creationDate: Sample.sep(3), updateDate: Sample.sep(5),
            lineData: Sample.ink("a-kjv-1"), layoutMetadataData: Sample.metadata
        )
        rowAKJV.notebook = Fixture.notebookA
        var rowB = BackupExportRowSeed(
            verse: 1, rowUUID: "B-1", creationDate: Sample.sep(6), updateDate: Sample.sep(7),
            lineData: Sample.ink("same"), layoutMetadataData: Sample.metadata
        )
        rowB.notebook = Fixture.notebookB
        var rowBExodus = BackupExportRowSeed(
            chapter: Sample.exodus3, verse: 2, rowUUID: "B-E3-2", creationDate: Sample.sep(6), updateDate: Sample.sep(8),
            lineData: Sample.ink("b-e3-2"), layoutMetadataData: Sample.metadata
        )
        rowBExodus.notebook = Fixture.notebookB
        let seeds = [defaultRow, rowA, rowAKJV, rowB, rowBExodus]
        try source.seed(seeds)
        // 필사책 정보 — 기본(이름을 바꿨다) · A(완료, 동기화 중복으로 옛 레코드가 하나 더) · B(모르는 상태 값 · 예약 필드) · ID 가 형식이 아닌 것.
        let infoDefault = Fixture.notebookRecord(.default, name: "아침 필사", updatedAt: Sample.sep(5))
        let infoA = Fixture.notebookRecord(
            Fixture.notebookA, name: "두 번째 필사", status: "completed", createdAt: Sample.sep(3), updatedAt: Sample.sep(6), completedAt: Sample.sep(6)
        )
        let infoAOlder = Fixture.notebookRecord(Fixture.notebookA, name: "옛 이름", createdAt: Sample.sep(3), updatedAt: Sample.sep(4))
        let infoB = Fixture.notebookRecord(
            Fixture.notebookB, name: "세 번째 필사", status: "paused-future", createdAt: Sample.sep(6), updatedAt: Sample.sep(7),
            kind: "group", scopeData: #"{"books":["GEN"]}"#, linkData: #"{"challenge":"advent"}"#
        )
        let infoBroken = BackupNotebookRecord(
            id: "NOT-A-NOTEBOOK", name: "깨진 것", status: nil, createdAt: nil, updatedAt: Sample.sep(9), completedAt: nil,
            kind: nil, scopeData: nil, linkData: nil
        )
        try source.seedNotebooks([infoAOlder, infoB, infoBroken, infoDefault, infoA])
        let progress = BackupProgressRecorder()

        // When: 내보낸다.
        let exported = try await source.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { progress.record($0) }
        let payload = try source.open(exported)

        // Then: 형식 2 — 필사책 목록은 필사책마다 하나(늦은 것), 기본 먼저 · 토큰 순, 형식이 아닌 ID 는 빠진다. 값은 원본 그대로.
        #expect(payload.manifest.formatVersion == 2)
        #expect(payload.manifest.notebooks == [infoDefault, infoA, infoB])
        // 진행은 필사책 · 권 · 장 자리 단위 — 기본 창세기 1 · A 창세기 1(개역개정 · KJV 한 자리) · B 창세기 1 · B 출애굽기 3.
        #expect(progress.events.first == BackupProgress(done: 0, total: 4))
        #expect(progress.events.last == BackupProgress(done: 4, total: 4))
        // 행 — 필사책 토큰(기본은 키 없음) · 번역본 · 권 코드, 출처 titleName 은 접두까지 원문 그대로. 대표는 필사책마다 따로다.
        let itemDefault = try #require(payload.row("D-1"))
        #expect(itemDefault.verse == BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 1))
        #expect(itemDefault.verse.notebook == nil)
        #expect(itemDefault.source.titleName == "1-01Genesis.txt")
        let itemA = try #require(payload.row("A-1"))
        #expect(itemA.verse == BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 1, notebook: Fixture.notebookA.rawValue))
        #expect(itemA.source.titleName == "nb_\(Fixture.notebookA.rawValue)~1-01Genesis.txt")
        let itemAKJV = try #require(payload.row("A-KJV-1"))
        #expect(itemAKJV.verse == BackupVerseKey(translation: "KJV", book: "GEN", chapter: 1, verse: 1, notebook: Fixture.notebookA.rawValue))
        #expect(itemAKJV.source.titleName == "nb_\(Fixture.notebookA.rawValue)~KJV-1-01Genesis.txt")
        let itemB = try #require(payload.row("B-1"))
        #expect(itemB.verse.notebook == Fixture.notebookB.rawValue)
        #expect(itemB.fingerprint == itemDefault.fingerprint)
        let allCurrent = [itemDefault, itemA, itemAKJV, itemB].allSatisfy(\.isCurrent)
        #expect(allCurrent)
        #expect(payload.row("B-E3-2")?.verse == BackupVerseKey(translation: "NKRV", book: "EXO", chapter: 3, verse: 2, notebook: Fixture.notebookB.rawValue))
        // 순서 — 기본 필사책 먼저, 그다음 토큰 순(A → B), 필사책 안에서 권 → 장 → 번역본.
        #expect(payload.items.map(\.source.rowKey) == ["D-1", "A-1", "A-KJV-1", "B-1", "B-E3-2"])

        // Given: 불러오는 기기 — 기본 필사책 1절에 같은 내용(same)이 이미 있다. 필사책 정보는 없다.
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        try harness.seed([
            BackupExportRowSeed(
                verse: 1, rowUUID: "STORED-D-1", creationDate: Sample.sep(1), updateDate: Sample.sep(2),
                lineData: Sample.ink("same"), layoutMetadataData: Sample.metadata
            )
        ])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When: 불러온다.
        let inspection = try await importer.inspect(fileURL: exported.fileURL, password: BackupExportSample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 미리보기 — 장은 필사책별, 기본 1절만 같은 내용이고 B 1절(같은 잉크)은 다른 필사책이라 새로 넣는다. 필사책 셋.
        let pageDefault = Sample.page(Sample.genesis1)
        let pageA = Sample.page(Sample.genesis1, notebook: Fixture.notebookA)
        let pageAKJV = Sample.page(Fixture.kjvGenesis1, notebook: Fixture.notebookA)
        let pageB = Sample.page(Sample.genesis1, notebook: Fixture.notebookB)
        let pageBExodus = Sample.page(Sample.exodus3, notebook: Fixture.notebookB)
        #expect(inspection.preview.chapters == [pageDefault, pageA, pageAKJV, pageB, pageBExodus])
        #expect(inspection.preview.new == 4)
        #expect(inspection.preview.same == 1)
        #expect(inspection.preview.notebooks == 3)
        #expect(inspection.preview.itemCount == seeds.count)
        #expect(report == .completed(BackupImportTally(new: 4, same: 1)))

        // Then: 장마다 그 필사책 행만 — 권 이름(접두) · 번역 열 · 바이트 · 시각 · 현재 여부가 원본 그대로다.
        #expect(try await harness.rows(page: pageDefault).map(\.rowKey) == ["STORED-D-1"])
        for seed in [rowA, rowAKJV, rowB, rowBExodus] {
            let imported = try await harness.rows(page: seed.page)
            #expect(imported.count == 1, "\(seed.rowKey)")
            let original = seed.record
            let match = try #require(imported.first)
            #expect(match.titleName == original.titleName, "\(seed.rowKey)")
            #expect(match.backupNotebook == seed.notebook, "\(seed.rowKey)")
            #expect(match.translation == original.translation, "\(seed.rowKey)")
            #expect(match.lineData == original.lineData, "\(seed.rowKey)")
            #expect(match.layoutMetadataData == original.layoutMetadataData, "\(seed.rowKey)")
            #expect(match.drawingVersion == original.drawingVersion, "\(seed.rowKey)")
            #expect(match.creationDate == original.creationDate, "\(seed.rowKey)")
            #expect(match.updateDate == original.updateDate, "\(seed.rowKey)")
            #expect(match.isPresent == true, "\(seed.rowKey)")
            // business id 도 필사책 권 이름으로 짓는다 — 기본 필사책 행 형식과 겹치지 않는다.
            #expect(match.businessID?.hasPrefix(original.titleName + ".") == true, "\(seed.rowKey)")
        }
        let stored = try ModelContext(harness.container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(stored.count == 1 + 4)
        // 영어 행의 번역 열은 다른 필사책이어도 nil 이다(열에 영어 값을 쓰지 않는다).
        let columnsAreSafe = stored.allSatisfy { $0.translation == nil || $0.translation == .NKRV }
        #expect(columnsAreSafe)

        // Then: 필사책 정보 — 이 기기에 없던 셋을 원본 그대로 넣었다(모르는 상태 값 · 예약 필드 포함).
        #expect(try harness.storedNotebooks() == Fixture.sorted([infoDefault, infoA, infoB]))
        // Then: 바뀐 장마다 필사책과 함께 알린다 — 같은 내용이라 쓰지 않은 기본 필사책 장은 알리지 않는다.
        #expect(Set(harness.changes.posted.map(\.page)) == [pageA, pageAKJV, pageB, pageBExodus])
    }

    @Test("다른 필사책 초안도 그 필사책으로 담는다 — 기본 필사책 초안의 id 는 2.1 과 같고, 세션 · 절 · revision · 잉크가 같은 두 필사책 초안의 id 는 겹치지 않는다")
    func otherNotebookDraftsAreExported() async throws {
        // Given: 내보내는 기기(로그인하지 않음) — A 창세기 1장 2절에 행 하나. 초안 셋(이 기기 전용 묶음, 빈 절에 써서 화면에 겹친다) —
        //   기본 창세기 1:3 · A 창세기 1:3(세션 · revision · 잉크가 같고 필사책만 다르다) · B 출애굽기 3:2(B 에는 행이 없다 — 자리는 초안 요약에서 온다).
        let source = try BackupExportHarness()
        defer { source.remove() }
        var rowA = BackupExportRowSeed(
            verse: 2, rowUUID: "A-2", creationDate: Sample.sep(3), updateDate: Sample.sep(4),
            lineData: Sample.ink("a-2"), layoutMetadataData: Sample.metadata
        )
        rowA.notebook = Fixture.notebookA
        try source.seed([rowA])
        let sameInk = Sample.ink("같은 초안")
        let inkB = Sample.ink("b-초안")
        try await source.save([
            BackupExportSample.draft(verse: 3, ink: sameInk, account: .localOnly),
            BackupExportSample.draft(notebook: Fixture.notebookA, verse: 3, ink: sameInk, account: .localOnly),
            BackupExportSample.draft(chapter: Sample.exodus3, notebook: Fixture.notebookB, verse: 2, ink: inkB, account: .localOnly)
        ])
        let progress = BackupProgressRecorder()

        // When: 내보낸다.
        let exported = try await source.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { progress.record($0) }
        let payload = try source.open(exported)

        // Then: 자리는 기본 창세기 1 · A 창세기 1 · B 출애굽기 3 — B 는 초안만 있는 자리다.
        #expect(progress.events.last == BackupProgress(done: 3, total: 3))
        #expect(payload.manifest.counts.rows == 1 && payload.manifest.counts.drafts == 3)
        // 초안 항목의 필사책 토큰 — 기본은 키 없음, 다른 필사책은 그 토큰. 모두 화면에 겹치던 초안이라 현재이고, A 2절의 행도 그대로 현재다.
        let drafts = payload.items.filter { $0.kind == .draft }
        #expect(drafts.map(\.verse) == [
            BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 3),
            BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 3, notebook: Fixture.notebookA.rawValue),
            BackupVerseKey(translation: "NKRV", book: "EXO", chapter: 3, verse: 2, notebook: Fixture.notebookB.rawValue)
        ])
        let allCurrent = drafts.allSatisfy(\.isCurrent)
        #expect(allCurrent)
        #expect(payload.row("A-2")?.isCurrent == true)
        // id — 기본 필사책 초안은 2.1 과 같은 원본 키, 다른 필사책 초안은 끝에 필사책 토큰을 더한다. 지문이 같아도 id 는 겹치지 않는다.
        let fingerprint = BackupExportSample.fingerprint(sameInk)
        let draftID: (String?) -> String = { notebook in
            let sourceKey = BackupItemID.draftSourceKey(
                draftScope: "local", sessionID: "session-1", translation: "NKRV", title: BibleTitle.genesis.rawValue, chapter: 1, verse: 3,
                revision: 3, notebook: notebook
            )
            return BackupItemID.make(kind: .draft, sourceKey: sourceKey, fingerprint: fingerprint)
        }
        #expect(drafts.first?.id == draftID(nil))
        #expect(drafts.dropFirst().first?.id == draftID(Fixture.notebookA.rawValue))
        #expect(drafts.prefix(2).map(\.fingerprint) == [fingerprint, fingerprint])

        // Given: 불러오는 기기 — 비어 있다.
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When: 불러온다.
        let inspection = try await importer.inspect(fileURL: exported.fileURL, password: BackupExportSample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 초안은 그 필사책의 장으로 — 같은 잉크의 기본 · A 초안이 각자의 필사책에 현재로 하나씩 들어가고, B 초안은 B 의 행이다.
        #expect(report == .completed(BackupImportTally(new: 4)))
        let pageA = Sample.page(Sample.genesis1, notebook: Fixture.notebookA)
        let pageB = Sample.page(Sample.exodus3, notebook: Fixture.notebookB)
        #expect(try await harness.rows().map(\.lineData) == [sameInk])
        #expect(try await harness.representative(page: pageA, verse: 3)?.lineData == sameInk)
        #expect(try await harness.representative(page: pageA, verse: 2)?.lineData == Sample.ink("a-2"))
        let rowsB = try await harness.rows(page: pageB)
        #expect(rowsB.map(\.lineData) == [inkB])
        #expect(rowsB.map(\.titleName) == ["nb_\(Fixture.notebookB.rawValue)~1-02Exodus.txt"])
    }

    // MARK: - 형식 버전

    @Test("형식 1 파일(2.1)은 읽고 전부 기본 필사책에 넣는다 — 항목에 필사책 키가 있어도 읽지 않는다")
    func formatOneFileGoesToTheDefaultNotebook() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 형식 1 파일 — 하나는 필사책 키가 붙어 있다(형식 1 은 늘 nil 이어야 한다).
        let plain = BackupRestoreEntry(
            verse: 1, sourceKey: "OLD-1", ink: Sample.ink("old-1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
        let tagged = BackupRestoreEntry(
            verse: 2, sourceKey: "OLD-2", ink: Sample.ink("old-2"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2),
            notebook: Fixture.notebookA.rawValue
        )
        let file = try harness.writeBackup([plain, tagged], formatVersion: 1)
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 기본 필사책의 창세기 1장 하나 — 필사책 하나, 새 현재 둘.
        #expect(inspection.manifest?.formatVersion == 1)
        #expect(inspection.manifest?.notebooks == [])
        #expect(inspection.preview.chapters == [Sample.page(Sample.genesis1)])
        #expect(inspection.preview.notebooks == 1)
        #expect(inspection.preview.new == 2)
        #expect(inspection.preview.unknownNotebook == 0)
        #expect(report == .completed(BackupImportTally(new: 2)))
        let rows = try await harness.rows()
        #expect(rows.map(\.lineData) == [Sample.ink("old-1"), Sample.ink("old-2")])
        let allDefault = rows.allSatisfy { $0.titleName == "1-01Genesis.txt" && $0.backupNotebook == .default }
        #expect(allDefault)
        #expect(try await harness.rows(page: Sample.page(Sample.genesis1, notebook: Fixture.notebookA)).isEmpty)
        #expect(try harness.storedNotebooks().isEmpty)
    }

    @Test("형식 3(뒤 버전)은 파일 전체를 거부하고 아무것도 남기지 않는다 — manifest 는 1 · 2 만 읽고, 필사책 목록은 2 부터만 읽는다")
    func formatThreeIsRejected() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entry = BackupRestoreEntry(
            verse: 1, sourceKey: "NEXT", ink: Sample.ink("next"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
        let newer = try harness.writeBackup([entry], formatVersion: 3)
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When · Then
        await #expect(throws: BackupImportError.unsupportedFormat(formatVersion: 3)) {
            _ = try await importer.inspect(fileURL: newer, password: Sample.password)
        }
        #expect(harness.workLeftovers().isEmpty)
        #expect(harness.jobLeftovers().isEmpty)
        #expect(try await harness.rows().isEmpty)

        // manifest — 형식 1 은 필사책 목록 키가 있어도 읽지 않고, 형식 2 는 키가 없으면 빈 목록이다.
        let manifestBody = #""backupID":"B","createdAt":0,"appVersion":"2.2.0","scope":{"rows":true,"drafts":true},"#
            + #""counts":{"rows":0,"drafts":0,"blobs":0},"blobs":[]"#
        let notebooks = #","notebooks":[{"id":"default","name":"아침 필사"}]"#
        let formatOne = try BackupFormat.decoder.decode(BackupManifest.self, from: Data(("{\"formatVersion\":1," + manifestBody + notebooks + "}").utf8))
        #expect(formatOne.notebooks.isEmpty)
        let formatTwo = try BackupFormat.decoder.decode(BackupManifest.self, from: Data(("{\"formatVersion\":2," + manifestBody + notebooks + "}").utf8))
        #expect(formatTwo.notebooks.map(\.id) == ["default"])
        #expect(formatTwo.notebooks.first?.name == "아침 필사")
        let formatTwoWithoutList = try BackupFormat.decoder.decode(BackupManifest.self, from: Data(("{\"formatVersion\":2," + manifestBody + "}").utf8))
        #expect(formatTwoWithoutList.notebooks.isEmpty)
        #expect(throws: BackupFormatError.unsupportedFormat(formatVersion: 3)) {
            try BackupFormat.decoder.decode(BackupManifest.self, from: Data(("{\"formatVersion\":3," + manifestBody + notebooks + "}").utf8))
        }
        // 형식 1 manifest 를 쓰면 2.1 이 쓰던 모양 그대로다(필사책 목록 키가 없다).
        let written = try BackupFormat.encoder.encode(formatOne)
        #expect(String(bytes: written, encoding: .utf8)?.contains("notebooks") == false)
    }

    // MARK: - 알 수 없는 필사책

    @Test("알 수 없는 필사책 토큰의 항목만 건너뛰고 따로 센다 — 기본 필사책에 넣지 않고 파일은 받는다")
    func unknownNotebookItemsAreSkipped() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 기본 1절 · 「default」 를 적은 4절 · A 1절은 넣고, 형식이 아닌 토큰 둘(하나는 번역본도 모른다)은 건너뛴다.
        let plain = BackupRestoreEntry(
            verse: 1, sourceKey: "D-1", ink: Sample.ink("d-1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
        let explicitDefault = BackupRestoreEntry(
            verse: 4, sourceKey: "D-4", ink: Sample.ink("d-4"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2),
            notebook: "default"
        )
        let inA = BackupRestoreEntry(
            verse: 1, sourceKey: "A-1", ink: Sample.ink("a-1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2),
            notebook: Fixture.notebookA.rawValue
        )
        let badToken = BackupRestoreEntry(
            verse: 2, sourceKey: "BAD-1", ink: Sample.ink("bad-1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2),
            notebook: "NOT-A-TOKEN"
        )
        let upperToken = BackupRestoreEntry(
            verse: 3, sourceKey: "BAD-2", ink: Sample.ink("bad-2"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2),
            translation: "ESV", notebook: Fixture.notebookA.rawValue.uppercased()
        )
        let entries = [plain, explicitDefault, inA, badToken, upperToken]
        #expect(entries.map { BackupItemSupport.hasUnknownNotebook($0.item) } == [false, false, false, true, true])
        #expect(BackupImportPlanner.page(of: badToken.item) == nil)
        #expect(BackupImportPlanner.page(of: explicitDefault.item) == Sample.page(Sample.genesis1))
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: try harness.writeBackup(entries), password: Sample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 미리보기 — 알 수 없는 필사책 둘(번역본이 함께 틀려도 한 번만, 사유 열거형에는 넣지 않는다), 넣을 수 없는 것 수에 든다.
        #expect(inspection.preview.unknownNotebook == 2)
        #expect(inspection.preview.unsupported.isEmpty)
        #expect(inspection.preview.unsupportedCount == 2)
        #expect(inspection.preview.new == 3)
        #expect(inspection.preview.itemCount == entries.count)
        #expect(inspection.preview.notebooks == 2)
        #expect(inspection.preview.chapters == [Sample.page(Sample.genesis1), Sample.page(Sample.genesis1, notebook: Fixture.notebookA)])
        #expect(report == .completed(BackupImportTally(new: 3)))

        // Then: 저장소 — 기본 1 · 4절과 A 1절뿐, 건너뛴 잉크는 어디에도 없다.
        #expect(try await harness.rows().map(\.lineData) == [Sample.ink("d-1"), Sample.ink("d-4")])
        let rowsA = try await harness.rows(page: Sample.page(Sample.genesis1, notebook: Fixture.notebookA))
        #expect(rowsA.map(\.lineData) == [Sample.ink("a-1")])
        let stored = try ModelContext(harness.container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(stored.count == 3)
        let skippedInk = stored.contains { $0.lineData == Sample.ink("bad-1") || $0.lineData == Sample.ink("bad-2") }
        #expect(!skippedInk)
    }

}

/// 이 스위트가 막는 것:
/// - 이 기기에서 더 늦게 바꾼 필사책 정보를 백업의 옛 정보로 덮거나, 동기화 중복 레코드 하나만 바꾸는 것
/// - 같은 내용의 다른 필사책 항목을 판정기가 같은 절로 보는 것
/// - 2.1 이 남긴 멈춘 불러오기 기록을 읽지 못해 업데이트 뒤 이어 하지 못하는 것
@Suite("필사 백업 — 필사책 정보 · 판정 단위 · 작업 기록")
struct BackupNotebookInfoRestoreTesting {
    private typealias Sample = BackupRestoreSample
    private typealias Fixture = BackupNotebookFixture

    // MARK: - 필사책 정보

    @Test("필사책 정보 — 같은 ID 면 updatedAt 이 늦은 쪽을 남기고(그 ID 레코드 전부), 없으면 넣으며, 다시 불러와도 그대로다")
    func notebookInfoKeepsTheLaterRecord() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 이 기기 — A(9/5 옛 이름), B(9/20 이 기기에서 바꾼 이름 + 9/1 동기화 중복).
        let storedA = Fixture.notebookRecord(Fixture.notebookA, name: "옛 이름 A", updatedAt: Sample.sep(5))
        let storedB = Fixture.notebookRecord(Fixture.notebookB, name: "기기에서 바꾼 B", updatedAt: Sample.sep(20))
        let storedBDuplicate = Fixture.notebookRecord(Fixture.notebookB, name: "B 중복", updatedAt: Sample.sep(1))
        try harness.seedNotebooks([storedA, storedB, storedBDuplicate])
        // 백업 — A · B 는 9/10, C · 기본은 이 기기에 없다. ID 가 형식이 아닌 레코드 하나. C 에 필기 하나.
        let backupA = Fixture.notebookRecord(
            Fixture.notebookA, name: "백업 이름 A", status: "completed", updatedAt: Sample.sep(10), completedAt: Sample.sep(10)
        )
        let backupB = Fixture.notebookRecord(Fixture.notebookB, name: "백업 이름 B", updatedAt: Sample.sep(10))
        let backupC = Fixture.notebookRecord(Fixture.notebookC, name: "새 필사책 C", createdAt: Sample.sep(9), updatedAt: Sample.sep(10))
        let backupDefault = Fixture.notebookRecord(.default, name: "아침 필사", updatedAt: Sample.sep(10))
        let broken = BackupNotebookRecord(
            id: "NOT-A-NOTEBOOK", name: "깨진 것", status: nil, createdAt: nil, updatedAt: Sample.sep(30), completedAt: nil,
            kind: nil, scopeData: nil, linkData: nil
        )
        let entryC = BackupRestoreEntry(
            verse: 1, sourceKey: "C-1", ink: Sample.ink("c-1"), isCurrent: true, createdAt: Sample.sep(10), updatedAt: Sample.sep(10),
            notebook: Fixture.notebookC.rawValue
        )
        let file = try harness.writeBackup([entryC], notebooks: [backupA, backupB, backupC, backupDefault, broken])
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: file, password: Sample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 필사책 수는 항목 ∪ 목록(형식이 맞는 것) — 기본 · A · B · C.
        #expect(inspection.preview.notebooks == 4)
        #expect(report == .completed(BackupImportTally(new: 1)))
        // A 는 백업이 늦어 바꿨고, B 는 이 기기가 늦어 두 레코드 모두 그대로, C · 기본은 넣었고, 깨진 것은 넣지 않았다.
        let expected = Fixture.sorted([backupA, storedB, storedBDuplicate, backupC, backupDefault])
        #expect(try harness.storedNotebooks() == expected)
        #expect(try await harness.rows(page: Sample.page(Sample.genesis1, notebook: Fixture.notebookC)).map(\.lineData) == [Sample.ink("c-1")])

        // When: 같은 파일을 다시 불러온다.
        let again = try await importer.apply(try await importer.inspect(fileURL: file, password: Sample.password)) { _ in }

        // Then: 필기는 같은 내용이라 건너뛰고, 필사책 정보도 바뀌지 않는다.
        #expect(again == .completed(BackupImportTally(same: 1)))
        #expect(try harness.storedNotebooks() == expected)
    }

    @Test("필사책 정보 복원 쓰기 — 넣음 · 바꿈 · 그대로 · 건너뜀을 세고, 목록 안 같은 ID 는 늦은 것이며, 세대가 다르면 아무것도 쓰지 않는다")
    func notebookRestoreCountsAndGeneration() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let storedA = Fixture.notebookRecord(Fixture.notebookA, name: "옛 이름 A", updatedAt: Sample.sep(5))
        let storedB = Fixture.notebookRecord(Fixture.notebookB, name: "기기에서 바꾼 B", updatedAt: Sample.sep(20))
        try harness.seedNotebooks([storedA, storedB])
        let backupA = Fixture.notebookRecord(Fixture.notebookA, name: "백업 이름 A", updatedAt: Sample.sep(10))
        let olderBackupA = Fixture.notebookRecord(Fixture.notebookA, name: "더 옛 백업 A", updatedAt: Sample.sep(8))
        let backupB = Fixture.notebookRecord(Fixture.notebookB, name: "백업 이름 B", updatedAt: Sample.sep(10))
        let backupC = Fixture.notebookRecord(Fixture.notebookC, name: "새 필사책 C", updatedAt: Sample.sep(10))
        let broken = BackupNotebookRecord(
            id: "default-ish", name: nil, status: nil, createdAt: nil, updatedAt: nil, completedAt: nil, kind: nil, scopeData: nil, linkData: nil
        )
        let records = [olderBackupA, backupB, broken, backupC, backupA]

        // When: 적용을 시작한 뒤 모든 필사가 지워졌다(명령의 세대가 지금과 다르다).
        let current = await harness.generation()
        let stale = DrawingStoreGeneration(raw: current.raw + 1)

        // Then: 아무것도 쓰지 않는다.
        await #expect(throws: DrawingRepositoryError.staleStoreGeneration) {
            _ = try await harness.restorer.restoreNotebooks(records, generation: stale)
        }
        #expect(try harness.storedNotebooks() == Fixture.sorted([storedA, storedB]))

        // When: 지금 세대로 쓴다.
        let outcome = try await harness.restorer.restoreNotebooks(records, generation: current)

        // Then: A 는 목록 안의 늦은 것(9/10)이 저장소(9/5)보다 늦어 바꾸고, B 는 저장소(9/20)가 늦어 그대로, C 는 넣고, 깨진 ID 는 건너뛴다.
        #expect(outcome == BackupNotebookRestoreOutcome(inserted: 1, updated: 1, unchanged: 1, skipped: 1))
        #expect(outcome.changedStore)
        #expect(try harness.storedNotebooks() == Fixture.sorted([backupA, storedB, backupC]))

        // When: 같은 목록을 다시 쓴다 → 그대로.
        let again = try await harness.restorer.restoreNotebooks(records, generation: current)
        #expect(again == BackupNotebookRestoreOutcome(unchanged: 3, skipped: 1))
        #expect(!again.changedStore)
        #expect(try harness.storedNotebooks() == Fixture.sorted([backupA, storedB, backupC]))
    }

    // MARK: - 판정 단위

    @Test("판정 단위 — 같은 내용이라도 필사책이 다르면 다른 절이고, 장 순서는 기본 필사책 먼저 · 나머지는 토큰 순이다")
    func plannerKeepsNotebooksApart() {
        typealias PlanSample = BackupImportPlanSample
        let ink = PlanSample.ink("same")
        let defaultItem = PlanSample.item("D", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2))
        var itemB = PlanSample.item("B", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2))
        itemB.verse.notebook = Fixture.notebookB.rawValue
        let defaultRow = PlanSample.row("ROW-D", ink: ink, isPresent: true, updatedAt: PlanSample.sep(1))
        let pageDefault = PlanSample.page
        let pageB = NotebookChapter(notebook: Fixture.notebookB, chapter: PlanSample.chapter)

        // 기본 필사책 장 — B 항목을 보지 않고, 같은 내용의 행이 있어 건너뛴다.
        let defaultPlan = BackupImportPlanner.plan(items: [defaultItem, itemB], unsupported: [:], current: [defaultRow], page: pageDefault)
        #expect(defaultPlan.decisions.map(\.itemID) == [defaultItem.id])
        #expect(defaultPlan.decision(for: defaultItem.id) == .skipSame)
        // B 장 — 기본 필사책 행을 보지 않아 새 현재로, 넣는 행의 권 이름에 B 접두가 붙는다.
        let planB = BackupImportPlanner.plan(items: [defaultItem, itemB], unsupported: [:], current: [defaultRow], page: pageB)
        #expect(planB.decisions.map(\.itemID) == [itemB.id])
        #expect(planB.decision(for: itemB.id) == .insertCurrent)
        #expect(planB.insertions.map(\.titleName) == ["nb_\(Fixture.notebookB.rawValue)~1-01Genesis.txt"])
        #expect(planB.insertions.map(\.page) == [pageB])

        // 장 순서 — 기본 필사책(창세기 1 · 2) → A → B.
        let genesis2 = BibleChapter(title: .genesis, chapter: 2)
        let pageA = NotebookChapter(notebook: Fixture.notebookA, chapter: PlanSample.chapter)
        let pageDefault2 = NotebookChapter(notebook: .default, chapter: genesis2)
        #expect(BackupImportPlanner.ordered([pageB, pageDefault2, pageA, pageDefault, pageB]) == [pageDefault, pageDefault2, pageA, pageB])

        // 백업 키 — 접두 행의 번역본 · 필사책은 접두를 벗겨 정한다(영어 행은 열이 nil 이어도 KJV).
        let prefixedKJV = BackupRowRecord(
            rowUUID: "R", businessID: nil, titleName: "nb_\(Fixture.notebookA.rawValue)~KJV-1-01Genesis.txt", chapter: 1, verse: 1,
            translation: nil, isPresent: true, creationDate: nil, updateDate: nil, drawingVersion: 3, lineData: ink, layoutMetadataData: nil
        )
        #expect(prefixedKJV.backupTranslation == "KJV")
        #expect(prefixedKJV.backupNotebook == Fixture.notebookA)
        #expect(defaultRow.backupNotebook == .default)
    }

    // MARK: - 작업 기록

    @Test("2.1 이 남긴 멈춘 불러오기 기록(끝난 장이 BibleChapter)은 기본 필사책의 장으로 읽고, 다시 쓰면 지금 모양이다")
    func legacyJobRecordReadsAsDefaultNotebook() throws {
        // Given: 2.1 모양의 job.json.
        let legacy = LegacyJobRecord(
            jobID: "00000000-0000-0000-0000-0000000000D1",
            targetScope: Sample.accountA,
            status: "stopped",
            doneChapters: [Sample.genesis1, Fixture.kjvGenesis1],
            tally: BackupImportTally(new: 2, same: 1),
            totalChapters: 3,
            createdAt: Sample.sep(1),
            updatedAt: Sample.sep(2)
        )
        let data = try BackupFormat.encoder.encode(legacy)

        // When
        let record = try BackupFormat.decoder.decode(BackupImportJobRecord.self, from: data)

        // Then
        #expect(record.jobID == legacy.jobID)
        #expect(record.targetScope == Sample.accountA)
        #expect(record.status == .stopped)
        #expect(record.doneChapters == [Sample.page(Sample.genesis1), Sample.page(Fixture.kjvGenesis1)])
        #expect(record.tally == legacy.tally)
        #expect(record.totalChapters == 3)
        #expect(record.recordVersion == BackupImportJobRecord.currentRecordVersion)

        // When: 다시 쓰고 읽는다 — 다른 필사책의 장도 그대로 왕복한다.
        var updated = record
        updated.doneChapters.append(Sample.page(Sample.exodus3, notebook: Fixture.notebookA))
        let reread = try BackupFormat.decoder.decode(BackupImportJobRecord.self, from: BackupFormat.encoder.encode(updated))
        #expect(reread == updated)
    }
}

/// 이 파일 시험들의 고정 표본 — 필사책 A · B · C 와 필사책 정보.
enum BackupNotebookFixture {
    /// 필사책 A · B · C — 토큰은 사전순으로 A → B → C 다(장 순서 시험).
    static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0A0A0A0A-0000-4000-8000-00000000000A")!)
    static let notebookB = NotebookID.make(uuid: UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000000B")!)
    static let notebookC = NotebookID.make(uuid: UUID(uuidString: "0C0C0C0C-0000-4000-8000-00000000000C")!)

    static let kjvGenesis1 = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)

    /// 필사책 정보 하나 — 예약 필드는 주지 않으면 1차 값(`personal` · nil)이다.
    static func notebookRecord(
        _ notebook: NotebookID,
        name: String?,
        status: String? = "active",
        createdAt: Date? = BackupRestoreSample.sep(1),
        updatedAt: Date?,
        completedAt: Date? = nil,
        kind: String? = "personal",
        scopeData: String? = nil,
        linkData: String? = nil
    ) -> BackupNotebookRecord {
        BackupNotebookRecord(
            id: notebook.rawValue,
            name: name,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            kind: kind,
            scopeData: scopeData,
            linkData: linkData
        )
    }

    /// 저장소에서 읽은 필사책 정보와 견줄 순서 — `BackupRestoreHarness.storedNotebooks()` 와 같다.
    static func sorted(_ records: [BackupNotebookRecord]) -> [BackupNotebookRecord] {
        records.sorted { ($0.id, $0.name ?? "") < ($1.id, $1.name ?? "") }
    }
}

/// 2.1 의 작업 기록(`job.json`) 모양 — 끝난 장이 `BibleChapter` 다.
private struct LegacyJobRecord: Encodable {
    var recordVersion = 1
    let jobID: String
    let targetScope: AccountScope?
    let status: String
    let doneChapters: [BibleChapter]
    let tally: BackupImportTally
    let totalChapters: Int
    let createdAt: Date
    let updatedAt: Date
}
