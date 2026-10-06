//
//  BackupImportPlanPinTesting.swift
//  DomainTest
//
//  불러오기 판정 — 대표 고정(오케스트레이터 결정 2026-10-06). isPresent 행이 없는 legacy 절에 보관 행만 넣을 때 지금 대표를 고정한다.
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 1.3.0 legacy 절(`isPresent` 가 모두 false · nil)에 더 늦은 다른 내용을 보관으로 넣어, 대표 규칙이 전체 행에서 고르며 **화면의 필사가 바뀌는 것**
/// - 지운 legacy 절(비운 대표가 present 아님)에 더 늦은 보관 잉크가 대표로 올라가 지운 절에 필기가 보이는 것
/// - 고정이 필요 없는 절(present 행이 있음 · 현재로 넣음 · 행 없음 · 넣는 행 없음)에 고정을 내는 것
@Suite("불러오기 판정 — 대표 고정")
struct BackupImportPlanPinTesting {
    private typealias Sample = BackupImportPlanSample

    private let inkL = Sample.ink("legacy-L")
    private let inkM = Sample.ink("legacy-M")

    /// 1.3.0 의 절 — 대표 L(9/10, isPresent false)과 그보다 이른 M(9/05, isPresent nil).
    private var legacyRows: [BackupRowRecord] {
        [
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000100", ink: inkL, isPresent: false, updatedAt: Sample.sep(10)),
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000050", ink: inkM, isPresent: nil, updatedAt: Sample.sep(5))
        ]
    }

    @Test("legacy 절에 더 늦은 다른 내용을 보관으로 넣으면 지금 대표를 고정하고, 적용 뒤에도 대표가 그대로다")
    func legacyVerseKeepsItsRepresentative() throws {
        // Given — 백업의 현재 필기 Y(9/20)와 보관 필기 Z(9/25): 둘 다 지금 대표보다 늦고 내용이 다르다
        let inkY = Sample.ink("Y")
        let inkZ = Sample.ink("Z")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20))
        let backupArchive = Sample.item("Z", ink: inkZ, isCurrent: false, updatedAt: Sample.sep(25))

        // When
        let plan = Sample.plan([backupCurrent, backupArchive], current: legacyRows)

        // Then — 잉크 있는 대표가 있으니 둘 다 보관이고, 지금 대표 L 을 고정한다. 미리보기 수는 그대로다
        #expect(plan.decision(for: backupCurrent.id) == .insertArchived)
        #expect(plan.decision(for: backupArchive.id) == .insertArchived)
        #expect(plan.pins == [BackupRepresentativePin(verse: 1, rowKey: "1-01Genesis.txt.1.1.1700000100")])
        #expect(plan.preview.archived == 2)
        #expect(plan.preview.itemCount == 2)

        // Then — 적용했다고 치면(넣을 행 + L.isPresent = true) 대표는 그대로 L 이다
        let stored = Sample.applying(plan, to: legacyRows, blobs: [inkY, inkZ])
        let representative = try #require(Sample.representative(of: stored))
        #expect(representative.rowKey == "1-01Genesis.txt.1.1.1700000100")
        #expect(representative.lineData == inkL)
        // 고정하지 않았다면 대표 규칙이 전체 행에서 골라 가장 늦은 Z 가 보였다
        let unpinned = BackupChapterPlan(chapter: plan.chapter, decisions: plan.decisions, insertions: plan.insertions)
        #expect(Sample.representative(of: Sample.applying(unpinned, to: legacyRows, blobs: [inkY, inkZ]))?.lineData == inkZ)

        // Then — 다시 불러오면 넣을 행도 고정도 없다
        let again = Sample.plan([backupCurrent, backupArchive], current: stored)
        #expect(again.insertions.isEmpty)
        #expect(again.pins.isEmpty)
    }

    @Test("isPresent 행이 있는 절 · 넣는 행이 없는 절은 고정하지 않는다 — 고정은 절마다다")
    func presentRowOrNothingToInsertMeansNoPin() {
        // Given — 1절은 legacy(present 없음), 2절은 present 대표가 있다. 둘 다 더 늦은 다른 내용을 보관으로 받는다
        let inkY = Sample.ink("Y")
        let rows = legacyRows + [
            Sample.row("X2", verse: 2, ink: Sample.ink("X2"), isPresent: true, updatedAt: Sample.sep(10)),
            Sample.row("W2", verse: 2, ink: Sample.ink("W2"), isPresent: false, updatedAt: Sample.sep(5))
        ]
        let verse1 = Sample.item("Y1", ink: inkY, isCurrent: false, updatedAt: Sample.sep(20))
        let verse2 = Sample.item("Y2", verse: 2, ink: inkY, isCurrent: false, updatedAt: Sample.sep(20))

        // When
        let plan = Sample.plan([verse1, verse2], current: rows)

        // Then — present 대표가 있는 2절은 고정하지 않는다
        #expect(plan.decision(for: verse1.id) == .insertArchived)
        #expect(plan.decision(for: verse2.id) == .insertArchived)
        #expect(plan.pins.map(\.verse) == [1])

        // Then — legacy 절이어도 넣는 행이 없으면(같은 내용뿐) 고정하지 않는다
        let sameAsL = Sample.item("L-COPY", ink: inkL, isCurrent: true, updatedAt: Sample.sep(10), drawingVersion: 1, metadata: nil)
        let samePlan = Sample.plan([sameAsL], current: legacyRows)
        #expect(samePlan.decision(for: sameAsL.id) == .skipSame)
        #expect(samePlan.pins.isEmpty)
    }

    @Test("현재로 넣는 절은 고정하지 않는다 — 새 present 행이 대표가 된다")
    func insertCurrentMeansNoPin() {
        // Given — 9/10 에 지운 legacy 절(비운 대표가 present 아님)과, 그보다 늦은 백업의 현재 필기 Y(9/20) · 보관 필기 Z(9/25)
        let rows = [
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000100", ink: nil, isPresent: false, updatedAt: Sample.sep(10)),
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000050", ink: inkM, isPresent: false, updatedAt: Sample.sep(5))
        ]
        let inkY = Sample.ink("Y")
        let inkZ = Sample.ink("Z")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20))
        let backupArchive = Sample.item("Z", ink: inkZ, isCurrent: false, updatedAt: Sample.sep(25))

        // When
        let plan = Sample.plan([backupCurrent, backupArchive], current: rows)

        // Then
        #expect(plan.decision(for: backupCurrent.id) == .insertCurrent)
        #expect(plan.decision(for: backupArchive.id) == .insertArchived)
        #expect(plan.pins.isEmpty)
        let stored = Sample.applying(plan, to: rows, blobs: [inkY, inkZ])
        #expect(Sample.representative(of: stored)?.lineData == inkY)
    }

    @Test("행이 없는 절은 고정하지 않는다 — 보관 항목 중 가장 늦은 것이 대표 규칙대로 보이는 것을 받아들인다")
    func emptyVerseMeansNoPin() {
        // Given — 백업에 현재 후보가 없는 절(보이지 않던 초안과 보관 행뿐)
        let inkHidden = Sample.ink("hidden-draft")
        let inkOld = Sample.ink("old")
        let hiddenDraft = Sample.item("local|S|NKRV|GEN|1|1|3", ink: inkHidden, isCurrent: false, updatedAt: Sample.sep(20), kind: .draft)
        let oldRow = Sample.item("OLD", ink: inkOld, isCurrent: false, updatedAt: Sample.sep(10))

        // When
        let plan = Sample.plan([hiddenDraft, oldRow])

        // Then — 빈 자리 행을 만들지 않는다(나중에 다른 기기에서 도착하는 legacy 행을 가린다)
        #expect(plan.decisions.allSatisfy { $0.decision == .insertArchived })
        #expect(plan.pins.isEmpty)
        let stored = Sample.applying(plan, to: [], blobs: [inkHidden, inkOld])
        #expect(Sample.representative(of: stored)?.lineData == inkHidden)
    }

    @Test("지운 legacy 절 — protectCleared 와 보관을 넣으며 비운 대표를 고정해 절은 비운 채로 남는다")
    func legacyClearedRepresentativeIsPinned() throws {
        // Given — 9/29 에 지운 legacy 절(비운 대표 C 가 present 아님)과 지운 잉크(9/15)
        let rows = [
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000200", ink: nil, isPresent: false, updatedAt: Sample.sep(29)),
            Sample.legacyRow("1-01Genesis.txt.1.1.1700000150", ink: Sample.ink("erased"), isPresent: false, updatedAt: Sample.sep(15))
        ]
        // 백업의 현재 필기 Y(9/20 — 지우기보다 이르다)와, 지우기보다 늦은 보관 필기 Z(10/01)
        let inkY = Sample.ink("Y")
        let inkZ = Sample.ink("Z")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20))
        let backupArchive = Sample.item("Z", ink: inkZ, isCurrent: false, updatedAt: Sample.oct(1))

        // When
        let plan = Sample.plan([backupCurrent, backupArchive], current: rows)

        // Then
        #expect(plan.decision(for: backupCurrent.id) == .protectCleared)
        #expect(plan.decision(for: backupArchive.id) == .insertArchived)
        #expect(plan.pins == [BackupRepresentativePin(verse: 1, rowKey: "1-01Genesis.txt.1.1.1700000200")])

        // Then — 적용 뒤 대표는 비운 행 C 다
        let stored = Sample.applying(plan, to: rows, blobs: [inkY, inkZ])
        let representative = try #require(Sample.representative(of: stored))
        #expect(representative.rowKey == "1-01Genesis.txt.1.1.1700000200")
        #expect(representative.lineData == nil)
        // 고정하지 않았다면 10/01 의 Z 가 대표로 올라가 지운 절에 필기가 보였다
        let unpinned = BackupChapterPlan(chapter: plan.chapter, decisions: plan.decisions, insertions: plan.insertions)
        #expect(Sample.representative(of: Sample.applying(unpinned, to: rows, blobs: [inkY, inkZ]))?.lineData == inkZ)
    }
}
