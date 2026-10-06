//
//  BackupImportPlanPreviewTesting.swift
//  DomainTest
//
//  불러오기 판정 — 지원 안 됨(사유별)과 미리보기(설계 §4-1 6단계 · §5-1 unsupported): 장 나누기 · 수 합 · 장 순서.
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 해석할 수 없는 항목을 조용히 바꾸거나 버리는 것 — 건너뛰고 사유별로 센다(정책 §6-2 · §8)
/// - 미리보기 수가 파일의 항목 수와 맞지 않는 것 — 빠지거나 두 번 세는 항목
/// - 적용이 장을 권 · 장 순서로 돌지 않는 것
@Suite("불러오기 판정 — 지원 안 됨 · 미리보기")
struct BackupImportPlanPreviewTesting {
    private typealias Sample = BackupImportPlanSample

    /// 풀리지 않는 메타데이터 — 뒤 버전의 형식일 수 있다.
    private let brokenMetadata = Data("깨진 메타데이터".utf8)

    /// 호출부가 하듯 항목마다 지원 판정을 한다 — 메타데이터 blob 은 표본 바이트에서 찾는다.
    private func reasons(_ items: [BackupItem]) -> [String: BackupUnsupportedReason] {
        let bytes = [
            BackupFormat.sha256Hex(Sample.layoutMetadata): Sample.layoutMetadata,
            BackupFormat.sha256Hex(brokenMetadata): brokenMetadata
        ]
        var reasons: [String: BackupUnsupportedReason] = [:]
        for item in items {
            reasons[item.id] = BackupItemSupport.reason(item) { bytes[$0] }
        }
        return reasons
    }

    @Test("지원 안 됨 — 판정에서 빼고 사유별로 센다")
    func unsupportedItemsAreSkippedByReason() {
        // Given — 창세기 1장에 놓이지만 해석할 수 없는 항목들
        let unknownTranslation = Sample.item("KJV", ink: Sample.ink("kjv"), isCurrent: true, updatedAt: Sample.sep(20), translation: "KJV")
        let undecodable = Sample.item("FUTURE", ink: Sample.ink("future"), isCurrent: true, updatedAt: Sample.sep(21), metadata: brokenMetadata)
        let unknownVersion = Sample.item(
            "V9", ink: Sample.ink("v9"), isCurrent: false, updatedAt: Sample.sep(5), drawingVersion: 9, metadata: nil
        )
        let verseZero = Sample.item("VERSE-0", verse: 0, ink: Sample.ink("zero"), isCurrent: true, updatedAt: Sample.sep(5))
        let items = [unknownTranslation, undecodable, unknownVersion, verseZero]

        // When
        let plan = Sample.plan(items, unsupported: reasons(items))

        // Then — 아무것도 넣지 않고, 적용할 때 판정할 것도 없다
        #expect(plan.decision(for: unknownTranslation.id) == .unsupported(.unknownTranslation))
        #expect(plan.decision(for: undecodable.id) == .unsupported(.undecodableMetadata))
        #expect(plan.decision(for: unknownVersion.id) == .unsupported(.unknownDrawingVersion))
        #expect(plan.decision(for: verseZero.id) == .unsupported(.outOfRange))
        #expect(plan.insertions.isEmpty)
        #expect(!plan.hasSupportedItems)
        #expect(plan.preview.unsupported == [.unknownTranslation: 1, .undecodableMetadata: 1, .unknownDrawingVersion: 1, .outOfRange: 1])
        #expect(plan.preview.chapters.isEmpty)
    }

    @Test("지원 안 되는 현재 항목은 현재 후보가 아니다 — 지원되는 다음 현재 항목이 후보다")
    func unsupportedItemIsNotTheCurrentCandidate() {
        // Given — 더 늦은 현재 항목의 메타데이터가 풀리지 않는다
        let future = Sample.item("FUTURE", ink: Sample.ink("future"), isCurrent: true, updatedAt: Sample.sep(25), metadata: brokenMetadata)
        let supported = Sample.item("SUPPORTED", ink: Sample.ink("ok"), isCurrent: true, updatedAt: Sample.sep(20))

        // When — 처리 순서는 지원 판정 → 현재 후보 → 나머지
        let plan = Sample.plan([future, supported], unsupported: reasons([future, supported]))

        // Then
        #expect(plan.decision(for: future.id) == .unsupported(.undecodableMetadata))
        #expect(plan.decision(for: supported.id) == .insertCurrent)
    }

    @Test("어느 장에도 놓을 수 없는 항목도 미리보기에서 사유별로 센다")
    func unplacedItemsAreCountedByReason() {
        // Given — 모르는 권 · 마지막 장 다음 · 0장 · 모르는 번역본과 권(번역본이 먼저다)
        let unknownBook = Sample.item("TOB", ink: Sample.ink("tob"), isCurrent: true, updatedAt: Sample.sep(1), book: "TOB")
        let pastLastChapter = Sample.item("GEN-51", ink: Sample.ink("gen51"), isCurrent: true, updatedAt: Sample.sep(1), chapter: 51)
        let chapterZero = Sample.item("GEN-0", ink: nil, isCurrent: true, updatedAt: Sample.sep(1), chapter: 0)
        let unknownBoth = Sample.item(
            "KJV-TOB", ink: Sample.ink("kjv"), isCurrent: true, updatedAt: Sample.sep(1), translation: "KJV", book: "TOB"
        )
        let items = [unknownBook, pastLastChapter, chapterZero, unknownBoth]

        // When · Then — 호출부가 사유를 넘겨도, 넘기지 않아도 같다(BackupItemSupport 와 같은 순서)
        for unsupported in [reasons(items), [:]] {
            let preview = BackupImportPlanner.preview(items: items, unsupported: unsupported, current: [:])
            #expect(preview.unsupported == [.unknownBook: 1, .outOfRange: 2, .unknownTranslation: 1])
            #expect(preview.chapters.isEmpty)
            #expect(preview.itemCount == items.count)
        }
        #expect(BackupImportPlanner.chapters(of: items).isEmpty)
    }

    @Test("미리보기 — 장마다 판정한 수를 모으고, 수의 합은 항목 수와 같다")
    func previewCountsEveryItemOnce() {
        // Given — 장 셋과 어느 장에도 놓을 수 없는 항목 하나를 섞어 넘긴다
        let genesis1 = BibleChapter(title: .genesis, chapter: 1)
        let genesis2 = BibleChapter(title: .genesis, chapter: 2)
        let exodus3 = BibleChapter(title: .exodus, chapter: 3)
        let inkStored = Sample.ink("stored")
        // 창세기 1장(빈 장) — 현재(new) · 보관(archived) · 현재 후보가 아닌 비운 항목(skippedEmpty)
        let newCurrent = Sample.item("G1-CURRENT", ink: Sample.ink("g1"), isCurrent: true, updatedAt: Sample.sep(20))
        let newArchive = Sample.item("G1-ARCHIVE", ink: Sample.ink("g1-old"), isCurrent: false, updatedAt: Sample.sep(10))
        let emptyArchive = Sample.item("G1-CLEARED", ink: nil, isCurrent: false, updatedAt: Sample.sep(5))
        // 창세기 2장 — 같은 내용(same) · 다른 현재(archived)
        let sameAsStored = Sample.item("G2-SAME", ink: inkStored, isCurrent: false, updatedAt: Sample.sep(10), chapter: 2)
        let otherCurrent = Sample.item("G2-CURRENT", ink: Sample.ink("g2"), isCurrent: true, updatedAt: Sample.sep(25), chapter: 2)
        // 출애굽기 3장 — 뒤에 지운 절(protectedCleared) · 모르는 번역본(unsupported)
        let protectedItem = Sample.item(
            "E3-CURRENT", ink: Sample.ink("e3"), isCurrent: true, updatedAt: Sample.sep(20), book: "EXO", chapter: 3
        )
        let unknownTranslation = Sample.item(
            "E3-KJV", ink: Sample.ink("kjv"), isCurrent: false, updatedAt: Sample.sep(20), translation: "KJV", book: "EXO", chapter: 3
        )
        // 어느 장에도 놓을 수 없다(unsupported)
        let unknownBook = Sample.item("TOB", ink: Sample.ink("tob"), isCurrent: true, updatedAt: Sample.sep(1), book: "TOB")
        let items = [unknownTranslation, otherCurrent, unknownBook, newArchive, protectedItem, sameAsStored, emptyArchive, newCurrent]
        let current: [BibleChapter: [BackupRowRecord]] = [
            genesis2: [Sample.row("G2-ROW", ink: inkStored, isPresent: true, updatedAt: Sample.sep(15), chapter: 2)],
            exodus3: [Sample.row("E3-CLEARED", ink: nil, isPresent: true, updatedAt: Sample.sep(29), title: .exodus, chapter: 3)]
        ]
        let unsupported = reasons(items)

        // When
        let preview = BackupImportPlanner.preview(items: items, unsupported: unsupported, current: current)

        // Then — 결정별 수
        #expect(preview.new == 1)
        #expect(preview.same == 1)
        #expect(preview.archived == 2)
        #expect(preview.protectedCleared == 1)
        #expect(preview.skippedEmpty == 1)
        #expect(preview.unsupported == [.unknownTranslation: 1, .unknownBook: 1])
        #expect(preview.insertCount == 4)
        #expect(preview.itemCount == items.count)
        // 장은 권 순서 → 장 순서
        #expect(preview.chapters == [genesis1, genesis2, exodus3])

        // Then — 검사가 장마다 읽으며 하나씩 더해도 같다
        var accumulated = BackupImportPreview(unsupported: BackupImportPlanner.unplaced(items: items, unsupported: unsupported))
        let grouped = BackupImportPlanner.itemsByChapter(items)
        for chapter in BackupImportPlanner.chapters(of: items) {
            let plan = BackupImportPlanner.plan(
                items: grouped[chapter] ?? [], unsupported: unsupported, current: current[chapter] ?? [], chapter: chapter
            )
            accumulated.add(plan)
        }
        #expect(accumulated == preview)
    }

    @Test("장은 권 순서 → 장 순서이고, 지원 항목이 없는 장은 미리보기의 장에 들지 않는다")
    func chaptersFollowBookOrder() {
        // Given — 권 · 장을 섞어 넘긴다. 마태복음 5장에는 모르는 번역본 항목뿐이다
        let matthew5 = BibleChapter(title: .matthew, chapter: 5)
        let items = [
            Sample.item("REV-22", ink: Sample.ink("rev"), isCurrent: true, updatedAt: Sample.sep(1), book: "REV", chapter: 22),
            Sample.item("GEN-10", ink: Sample.ink("gen10"), isCurrent: true, updatedAt: Sample.sep(1), chapter: 10),
            Sample.item("MAT-5-KJV", ink: Sample.ink("kjv"), isCurrent: true, updatedAt: Sample.sep(1), translation: "KJV", book: "MAT", chapter: 5),
            Sample.item("GEN-2", ink: Sample.ink("gen2"), isCurrent: true, updatedAt: Sample.sep(1), chapter: 2),
            Sample.item("MAT-1", ink: Sample.ink("mat"), isCurrent: true, updatedAt: Sample.sep(1), book: "MAT")
        ]
        let ordered = [
            BibleChapter(title: .genesis, chapter: 2),
            BibleChapter(title: .genesis, chapter: 10),
            BibleChapter(title: .matthew, chapter: 1),
            matthew5,
            BibleChapter(title: .revelation, chapter: 22)
        ]

        // When
        let preview = BackupImportPlanner.preview(items: items, unsupported: reasons(items), current: [:])

        // Then — 장 번호는 숫자 순서다(2 → 10)
        #expect(BackupImportPlanner.chapters(of: items) == ordered)
        #expect(preview.chapters == ordered.filter { $0 != matthew5 })
        #expect(preview.unsupported == [.unknownTranslation: 1])
        #expect(preview.new == 4)
    }

    @Test("새 행을 넣는 결정과 isPresent — 현재로 넣는 것만 present 다")
    func decisionInsertionFlags() {
        let inserting: [BackupImportDecision] = [.insertCurrent, .insertArchived, .protectCleared]
        let skipping: [BackupImportDecision] = [.skipSame, .skipEmpty, .unsupported(.unknownBook)]

        #expect(inserting.allSatisfy { $0.insertsRow })
        #expect(!skipping.contains { $0.insertsRow })
        #expect((inserting + skipping).filter(\.insertsAsPresent) == [.insertCurrent])
    }
}
