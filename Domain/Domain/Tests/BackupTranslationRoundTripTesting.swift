//
//  BackupTranslationRoundTripTesting.swift
//  DomainTest
//
//  필사 백업 · 불러오기의 번역본 — KJV · BSB 행 · 초안을 담고 되살리며 개역개정과 섞지 않는다
//  (설계 docs/backup-import-design.md §1-1 4 · §2-4 · §4-3 · §5-1, 영어 현지화 결정 1).
//

import Foundation
import SwiftData
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 영어 행(번역 열 nil)을 백업 키 null 로 담아, 불러온 기기에서 개역개정 필사로 섞는 것
/// - 불러오기가 SwiftData `translation` 열에 영어 값(.KJV · .BSB)을 쓰는 것 — 이미 나간 2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다
/// - 같은 권 · 장 · 절의 다른 번역본 행을 같은 내용 · 같은 대표로 판정하는 것
/// - 모르는 번역본(예: `"ESV"`) 항목을 어느 절에든 넣는 것
/// - KJV · BSB 초안을 백업에서 빼거나, 장 목록에 같은 권 · 장이 번역본별로 여러 번 올 때 같은 초안을 두 번 담는 것
@Suite("필사 백업 — 번역본(KJV · BSB)")
struct BackupTranslationRoundTripTesting {
    private typealias Sample = BackupRestoreSample

    private static let kjvGenesis1 = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
    private static let bsbGenesis1 = BibleChapter(title: .genesis, chapter: 1, translation: .BSB)
    private static let kjvGenesis2 = BibleChapter(title: .genesis, chapter: 2, translation: .KJV)
    private static let kjvGenesis3 = BibleChapter(title: .genesis, chapter: 3, translation: .KJV)

    /// 창세기 1장의 세 번역본 행 — 개역개정(열 nil · 열 NKRV), KJV(현재 · 보관), BSB. 영어 행의 열은 nil 이다.
    ///
    /// 1절은 번역본마다 현재 행이 있고 KJV · BSB 쪽이 더 늦다 — 영어 행을 개역개정 null 묶음으로 보면 개역개정 1절의 대표가 바뀐다.
    private var mixedSeeds: [BackupExportRowSeed] {
        [
            BackupExportRowSeed(
                verse: 1, rowUUID: "NKRV-NIL-1", translation: nil, creationDate: Sample.sep(1), updateDate: Sample.sep(2),
                lineData: Sample.ink("nkrv-nil-1"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "NKRV-2", translation: .NKRV, creationDate: Sample.sep(3), updateDate: Sample.sep(4),
                lineData: Sample.ink("nkrv-2"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                chapter: Self.kjvGenesis1, verse: 1, rowUUID: "KJV-1", translation: nil, creationDate: Sample.sep(5), updateDate: Sample.sep(6),
                lineData: Sample.ink("kjv-1"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                chapter: Self.kjvGenesis1, verse: 1, rowUUID: "KJV-1-OLD", translation: nil, isPresent: false,
                creationDate: Sample.sep(1), updateDate: Sample.sep(1), lineData: Sample.ink("kjv-1-old"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                chapter: Self.bsbGenesis1, verse: 1, rowUUID: "BSB-1", translation: nil, creationDate: Sample.sep(7), updateDate: Sample.sep(8),
                lineData: Sample.ink("bsb-1"), layoutMetadataData: Sample.metadata
            )
        ]
    }

    /// 표본 초안을 다른 번역본의 같은 절 초안으로 옮긴다(키만 바꾼다).
    private func moved(_ draft: VerseDraft, to chapter: BibleChapter) -> VerseDraft {
        var draft = draft
        draft.key = VerseDraftKey(sessionID: draft.key.sessionID, translation: chapter.translation, chapter: chapter, verse: draft.key.verse)
        return draft
    }

    /// 백업 전용 조회 모양의 행 하나(판정기 · 백업 키 시험용).
    private func record(_ rowKey: String, titleName: String, translation: String?, ink: Data?) -> BackupRowRecord {
        BackupRowRecord(
            rowUUID: rowKey,
            businessID: nil,
            titleName: titleName,
            chapter: 1,
            verse: 1,
            translation: translation,
            isPresent: true,
            creationDate: BackupImportPlanSample.sep(1),
            updateDate: BackupImportPlanSample.sep(1),
            drawingVersion: 3,
            lineData: ink,
            layoutMetadataData: BackupImportPlanSample.layoutMetadata
        )
    }

    // MARK: - 내보내기

    @Test("내보내기 — 영어 행은 titleName 접두의 번역본 · 권 코드로, 개역개정 행은 열 값 그대로 담고, 대표는 번역본마다 따로다")
    func exportKeysEnglishRowsByTitlePrefix() async throws {
        let harness = try BackupExportHarness()
        defer { harness.remove() }
        try harness.seed(mixedSeeds)
        let progress = BackupProgressRecorder()

        // When
        let result = try await harness.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { progress.record($0) }
        let payload = try harness.open(result)

        // Then: 행이 있는 장은 번역본별이고, 진행은 권 · 장 자리 단위(창세기 1장 하나)다.
        #expect(try await harness.database.backupPages() == [Sample.genesis1, Self.kjvGenesis1, Self.bsbGenesis1].map { Sample.page($0) })
        #expect(progress.events == [BackupProgress(done: 0, total: 1), BackupProgress(done: 1, total: 1)])

        // Then: 개역개정 행 — 열 값 그대로(nil 은 null), 원래 권 이름.
        let nkrvNil = try #require(payload.row("NKRV-NIL-1"))
        #expect(nkrvNil.verse == BackupVerseKey(translation: nil, book: "GEN", chapter: 1, verse: 1))
        #expect(nkrvNil.source.titleName == "1-01Genesis.txt")
        #expect(nkrvNil.isCurrent)
        #expect(payload.row("NKRV-2")?.verse == BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 1, verse: 2))

        // Then: 영어 행 — 열은 nil 이어도 키 번역본은 접두에서, 권 코드는 푼 권, 출처 이름은 원문 그대로. 대표는 번역본마다 따로다.
        let kjv = try #require(payload.row("KJV-1"))
        #expect(kjv.verse == BackupVerseKey(translation: "KJV", book: "GEN", chapter: 1, verse: 1))
        #expect(kjv.source.titleName == "KJV-1-01Genesis.txt")
        #expect(kjv.isCurrent)
        #expect(payload.row("KJV-1-OLD")?.isCurrent == false)
        let bsb = try #require(payload.row("BSB-1"))
        #expect(bsb.verse == BackupVerseKey(translation: "BSB", book: "GEN", chapter: 1, verse: 1))
        #expect(bsb.source.titleName == "BSB-1-01Genesis.txt")
        #expect(bsb.isCurrent)

        // Then: 순서 — 권 · 장 안에서 번역본 순서(개역개정 → KJV → BSB), 번역본 안에서 절 → 행 키.
        #expect(payload.items.map(\.source.rowKey) == ["NKRV-NIL-1", "NKRV-2", "KJV-1", "KJV-1-OLD", "BSB-1"])
    }

    @Test("내보내기 — KJV 초안도 담고, 장 목록에 같은 권 · 장이 번역본별로 여러 번 와도 초안마다 한 번만 담는다")
    func englishDraftsAreExportedOnce() async throws {
        let source = try BackupExportHarness()
        defer { source.remove() }
        // Given: 창세기 2장에 개역개정 행(5절) · KJV 행(6절)이 있어 행이 있는 장 목록에 창세기 2장이 번역본별로 두 번 온다
        //   (초안 요약이 장을 번역본별로 나눌 때와 같은 모양).
        try source.seed([
            BackupExportRowSeed(
                chapter: Sample.genesis2, verse: 5, rowUUID: "NKRV-2-5", lineData: Sample.ink("nkrv-row"),
                layoutMetadataData: BackupExportSample.metadata
            ),
            BackupExportRowSeed(
                chapter: Self.kjvGenesis2, verse: 6, rowUUID: "KJV-2-6", translation: nil, lineData: Sample.ink("kjv-row"),
                layoutMetadataData: BackupExportSample.metadata
            )
        ])
        // 로그인하지 않은 동안 쓴 초안 — 창세기 2장 1절에 개역개정 · KJV 하나씩, 행도 개역개정 초안도 없는 KJV 창세기 3장 1절에 하나.
        let nkrvDraft = BackupExportSample.draft(chapter: Sample.genesis2, verse: 1, ink: Sample.ink("nkrv-draft"), account: .localOnly)
        let kjvDraft = moved(
            BackupExportSample.draft(chapter: Sample.genesis2, verse: 1, ink: Sample.ink("kjv-draft"), account: .localOnly), to: Self.kjvGenesis2
        )
        let kjvOnlyDraft = moved(
            BackupExportSample.draft(chapter: Self.kjvGenesis3.backupPlace, verse: 1, ink: Sample.ink("kjv-only"), account: .localOnly),
            to: Self.kjvGenesis3
        )
        try await source.save([nkrvDraft, kjvDraft, kjvOnlyDraft])

        // When
        let exported = try await source.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let payload = try source.open(exported)

        // Then: 초안 셋이 한 번씩 — 번역본 키는 초안 키의 값 그대로다.
        let drafts = payload.items.filter { $0.kind == .draft }
        #expect(drafts.count == 3)
        #expect(Set(drafts.map(\.id)).count == 3)
        #expect(Set(drafts.map(\.verse)) == [
            BackupVerseKey(translation: "NKRV", book: "GEN", chapter: 2, verse: 1),
            BackupVerseKey(translation: "KJV", book: "GEN", chapter: 2, verse: 1),
            BackupVerseKey(translation: "KJV", book: "GEN", chapter: 3, verse: 1)
        ])
        #expect(payload.bytes(drafts.first { $0.verse.translation == "KJV" && $0.verse.chapter == 3 }?.inkBlob) == Sample.ink("kjv-only"))
        #expect(payload.row("KJV-2-6")?.verse == BackupVerseKey(translation: "KJV", book: "GEN", chapter: 2, verse: 6))
        // 잉크 다섯(행 둘 · 초안 셋)과 같은 메타데이터 하나.
        #expect(payload.manifest.counts == BackupCounts(rows: 2, drafts: 3, blobs: 6))

        // When: 빈 저장소에 불러온다.
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))
        _ = try await importer.apply(try await importer.inspect(fileURL: exported.fileURL, password: BackupExportSample.password)) { _ in }

        // Then: KJV 초안은 KJV 장(권 이름 접두 · 열 nil)에, 개역개정 초안은 개역개정 장에 들어간다.
        let kjvRows = try await harness.rows(Self.kjvGenesis2)
        #expect(Set(kjvRows.compactMap(\.lineData)) == [Sample.ink("kjv-draft"), Sample.ink("kjv-row")])
        let kjvRowsAreEnglish = kjvRows.allSatisfy { $0.titleName == "KJV-1-01Genesis.txt" && $0.translation == nil }
        #expect(kjvRowsAreEnglish)
        #expect(try await harness.rows(Self.kjvGenesis3).map(\.lineData) == [Sample.ink("kjv-only")])
        #expect(Set(try await harness.rows(Sample.genesis2).compactMap(\.lineData)) == [Sample.ink("nkrv-draft"), Sample.ink("nkrv-row")])
    }

    @Test("자리 — 번역본별로 나뉜 장 목록을 권 · 장 하나로 줄이고, 자리마다 번역본을 개역개정 → KJV → BSB 순서로 돈다")
    func placesCollapseTranslations() {
        let kjvExodus3 = BibleChapter(title: .exodus, chapter: 3, translation: .KJV)
        let split = [Self.kjvGenesis2, Sample.genesis2, Self.bsbGenesis1, Sample.genesis2, kjvExodus3]

        #expect(BibleChapter.backupPlaces(split) == [Sample.genesis1, Sample.genesis2, Sample.exodus3])
        #expect(Sample.genesis2.backupTranslationChapters == [
            Sample.genesis2, Self.kjvGenesis2, BibleChapter(title: .genesis, chapter: 2, translation: .BSB)
        ])
        #expect(Self.kjvGenesis2.backupPlace == Sample.genesis2)
        let pages = [Self.bsbGenesis1, Sample.genesis2, Self.kjvGenesis1, Sample.genesis1].map { Sample.page($0) }
        #expect(BackupImportPlanner.ordered(pages) == [
            Sample.genesis1, Self.kjvGenesis1, Self.bsbGenesis1, Sample.genesis2
        ].map { Sample.page($0) })
    }

    @Test("백업 키의 번역본 — titleName 접두가 먼저고, 접두 없는 행은 열 값 그대로(nil 은 null)")
    func rowBackupTranslation() {
        let ink = BackupImportPlanSample.ink("row")

        #expect(record("A", titleName: "1-01Genesis.txt", translation: nil, ink: ink).backupTranslation == nil)
        #expect(record("B", titleName: "1-01Genesis.txt", translation: "NKRV", ink: ink).backupTranslation == "NKRV")
        #expect(record("C", titleName: "KJV-1-01Genesis.txt", translation: nil, ink: ink).backupTranslation == "KJV")
        #expect(record("D", titleName: "BSB-1-01Genesis.txt", translation: nil, ink: ink).backupTranslation == "BSB")
        // 쓰지 않는 값 — 접두 없는 행의 영어 열은 앱이 개역개정으로 읽으므로 개역개정 묶음이다.
        #expect(record("E", titleName: "1-01Genesis.txt", translation: "KJV", ink: ink).backupTranslation == "NKRV")
    }

    // MARK: - 불러오기

    @Test("판정기 — 장은 번역본까지 맞는 항목 · 행만 보고, 모르는 번역본은 개역개정 장에서 지원 안 됨으로 센다")
    func plannerPlacesItemsByTranslation() {
        typealias PlanSample = BackupImportPlanSample
        let ink = PlanSample.ink("same")
        let nilItem = PlanSample.item("NIL", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2), translation: nil)
        let kjvItem = PlanSample.item("KJV", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2), translation: "KJV")
        let bsbItem = PlanSample.item("BSB", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2), translation: "BSB")
        let esvItem = PlanSample.item("ESV", ink: ink, isCurrent: true, updatedAt: PlanSample.sep(2), translation: "ESV")

        // 장 — nil · NKRV 는 개역개정, KJV · BSB 는 그 번역본, 모르는 번역본은 개역개정 장(지원 안 됨으로만 센다). 필사책은 기본.
        #expect(BackupImportPlanner.page(of: nilItem) == Sample.page(Sample.genesis1))
        #expect(BackupImportPlanner.page(of: kjvItem) == Sample.page(Self.kjvGenesis1))
        #expect(BackupImportPlanner.page(of: bsbItem) == Sample.page(Self.bsbGenesis1))
        #expect(BackupImportPlanner.page(of: esvItem) == Sample.page(Sample.genesis1))
        #expect(BackupImportPlanner.pages(of: [bsbItem, esvItem, kjvItem, nilItem]) == [
            Sample.genesis1, Self.kjvGenesis1, Self.bsbGenesis1
        ].map { Sample.page($0) })

        // 지금 행 — 같은 잉크의 KJV 행(열 nil · `KJV-` 접두)은 개역개정 장 판정에 들지 않는다.
        let kjvRow = record("ROW-KJV", titleName: "KJV-1-01Genesis.txt", translation: nil, ink: ink)
        let unsupported = [esvItem.id: BackupUnsupportedReason.unknownTranslation]
        let items = [nilItem, kjvItem, bsbItem, esvItem]
        let nkrvPlan = BackupImportPlanner.plan(items: items, unsupported: unsupported, current: [kjvRow], page: Sample.page(Sample.genesis1))
        #expect(nkrvPlan.decision(for: nilItem.id) == .insertCurrent)
        #expect(nkrvPlan.decision(for: esvItem.id) == .unsupported(.unknownTranslation))
        #expect(nkrvPlan.decision(for: kjvItem.id) == nil)
        #expect(nkrvPlan.insertions.map(\.titleName) == ["1-01Genesis.txt"])

        // KJV 장은 KJV 항목과 KJV 행만 본다 — 같은 내용이라 넣지 않는다.
        let kjvPlan = BackupImportPlanner.plan(items: items, unsupported: unsupported, current: [kjvRow], page: Sample.page(Self.kjvGenesis1))
        #expect(kjvPlan.decisions.map(\.itemID) == [kjvItem.id])
        #expect(kjvPlan.decision(for: kjvItem.id) == .skipSame)

        // BSB 장 — 같은 잉크의 KJV 행을 보지 않아 새 현재로, 넣는 행의 권 이름은 접두가 붙는다.
        let bsbPlan = BackupImportPlanner.plan(items: items, unsupported: unsupported, current: [kjvRow], page: Sample.page(Self.bsbGenesis1))
        #expect(bsbPlan.decision(for: bsbItem.id) == .insertCurrent)
        #expect(bsbPlan.insertions.map(\.titleName) == ["BSB-1-01Genesis.txt"])
    }

    @Test("왕복 — 번역본 키 · titleName · 열이 보존되고, 복원한 영어 행의 열은 nil 이며 번역본끼리 섞이지 않는다")
    func roundTripKeepsTranslationsApart() async throws {
        let source = try BackupExportHarness()
        defer { source.remove() }
        let seeds = mixedSeeds
        try source.seed(seeds)
        let exported = try await source.exporter(StubDrawingEditEnvironment(BackupExportSample.signedOut))
            .export(password: BackupExportSample.password) { _ in }
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: exported.fileURL, password: BackupExportSample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: 장은 번역본별이고, 번역본마다 현재 하나씩(개역개정은 1 · 2절) · KJV 보관 하나.
        #expect(inspection.preview.chapters == [Sample.genesis1, Self.kjvGenesis1, Self.bsbGenesis1].map { Sample.page($0) })
        #expect(inspection.preview.new == 4)
        #expect(inspection.preview.archived == 1)
        #expect(report.tally.insertCount == seeds.count)

        // Then: 장마다 그 번역본 행만, 권 이름 · 번역 열 · 바이트 · 시각이 원본 그대로다.
        for chapter in [Sample.genesis1, Self.kjvGenesis1, Self.bsbGenesis1] {
            let expected = seeds.filter { $0.chapter == chapter }.map(\.record)
            let imported = try await harness.rows(chapter)
            #expect(imported.count == expected.count, "\(chapter)")
            for original in expected {
                let match = imported.first { $0.verse == original.verse && $0.lineData == original.lineData }
                #expect(match?.titleName == original.titleName, "\(original.rowKey)")
                #expect(match?.translation == original.translation, "\(original.rowKey)")
                #expect(match?.layoutMetadataData == original.layoutMetadataData, "\(original.rowKey)")
                #expect(match?.creationDate == original.creationDate, "\(original.rowKey)")
                #expect(match?.updateDate == original.updateDate, "\(original.rowKey)")
                #expect(match?.isPresent == original.isPresent, "\(original.rowKey)")
            }
        }
        // Then: 1절 대표는 번역본마다 따로다 — 더 늦은 영어 행이 개역개정 1절을 가리지 않는다.
        #expect(try await harness.representative(Sample.genesis1, verse: 1)?.lineData == Sample.ink("nkrv-nil-1"))
        #expect(try await harness.representative(Self.kjvGenesis1, verse: 1)?.lineData == Sample.ink("kjv-1"))
        #expect(try await harness.representative(Self.bsbGenesis1, verse: 1)?.lineData == Sample.ink("bsb-1"))

        // Then: 저장소 전체 — 번역 열에는 .NKRV · nil 만 있다(영어 값을 쓰지 않는다).
        let stored = try ModelContext(harness.container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(stored.count == seeds.count)
        let columnsAreSafe = stored.allSatisfy { $0.translation == nil || $0.translation == .NKRV }
        #expect(columnsAreSafe)
        let englishColumns = stored.filter { $0.titleName?.hasPrefix("KJV-") == true || $0.titleName?.hasPrefix("BSB-") == true }.map(\.translation)
        #expect(englishColumns == [nil, nil, nil])
        #expect(Set(stored.compactMap(\.titleName)) == ["1-01Genesis.txt", "KJV-1-01Genesis.txt", "BSB-1-01Genesis.txt"])
    }

    @Test("불러오기 — 같은 내용이라도 번역본이 다르면 다른 절이다: 저장소의 영어 행은 개역개정 null 항목의 판정에 들지 않는다")
    func storedEnglishRowsDoNotJoinTheNilGroup() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 저장소 — KJV 1절 X(현재, 열 nil).
        let inkX = Sample.ink("X")
        try harness.seed([
            BackupExportRowSeed(
                chapter: Self.kjvGenesis1, verse: 1, rowUUID: "STORED-KJV", translation: nil, creationDate: Sample.sep(1), updateDate: Sample.sep(10),
                lineData: inkX, layoutMetadataData: Sample.metadata
            )
        ])
        // 백업 — 번역 null 1절 X(현재) · KJV 1절 Y(현재, 더 늦다).
        let nilEntry = BackupRestoreEntry(
            verse: 1, sourceKey: "NIL-X", ink: inkX, isCurrent: true, createdAt: Sample.sep(2), updatedAt: Sample.sep(3), translation: nil
        )
        let kjvEntry = BackupRestoreEntry(
            chapter: Self.kjvGenesis1, verse: 1, sourceKey: "KJV-Y", ink: Sample.ink("Y"), isCurrent: true,
            createdAt: Sample.sep(4), updatedAt: Sample.sep(20), translation: "KJV"
        )
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: try harness.writeBackup([nilEntry, kjvEntry]), password: Sample.password)
        _ = try await importer.apply(inspection) { _ in }

        // Then: 개역개정 장은 같은 내용의 KJV 행을 보지 않아 새 현재로, KJV 장은 잉크 있는 대표가 있어 보관으로 넣는다.
        #expect(inspection.preview.new == 1)
        #expect(inspection.preview.archived == 1)
        #expect(inspection.preview.same == 0)
        let nkrvRows = try await harness.rows(Sample.genesis1)
        #expect(nkrvRows.count == 1)
        #expect(nkrvRows.first?.matchesOriginal(nilEntry) == true)
        #expect(nkrvRows.first?.isPresent == true)
        let kjvRows = try await harness.rows(Self.kjvGenesis1)
        #expect(kjvRows.count == 2)
        let insertedKJV = try #require(kjvRows.first { $0.lineData == Sample.ink("Y") })
        #expect(insertedKJV.matchesOriginal(kjvEntry))
        #expect(insertedKJV.titleName == "KJV-1-01Genesis.txt")
        #expect(insertedKJV.translation == nil)
        #expect(try await harness.representative(Self.kjvGenesis1, verse: 1)?.rowKey == "STORED-KJV")
    }

    @Test("불러오기 — 모르는 번역본(ESV) 항목은 건너뛰고 사유로 세며, 어느 장에도 쓰지 않는다")
    func unknownTranslationIsSkipped() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let esvEntry = BackupRestoreEntry(
            verse: 1, sourceKey: "ESV-1", ink: Sample.ink("esv"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2), translation: "ESV"
        )
        let kjvEntry = BackupRestoreEntry(
            chapter: Self.kjvGenesis1, verse: 2, sourceKey: "KJV-2", ink: Sample.ink("kjv-2"), isCurrent: true,
            createdAt: Sample.sep(1), updatedAt: Sample.sep(2), translation: "KJV"
        )
        let importer = harness.importer(StubDrawingEditEnvironment(Sample.confirmed(Sample.accountA)))

        // When
        let inspection = try await importer.inspect(fileURL: try harness.writeBackup([esvEntry, kjvEntry]), password: Sample.password)
        let report = try await importer.apply(inspection) { _ in }

        // Then: ESV 는 지원 안 됨으로만 세고, 판정할 장은 KJV 창세기 1장뿐이다.
        #expect(inspection.preview.unsupported == [.unknownTranslation: 1])
        #expect(inspection.preview.new == 1)
        #expect(inspection.preview.chapters == [Sample.page(Self.kjvGenesis1)])
        #expect(report.tally.insertCount == 1)
        #expect(try await harness.rows(Sample.genesis1).isEmpty)
        let stored = try ModelContext(harness.container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(stored.map(\.titleName) == ["KJV-1-01Genesis.txt"])
        #expect(stored.map(\.translation) == [nil])
        #expect(stored.map(\.lineData) == [Sample.ink("kjv-2")])
    }
}
