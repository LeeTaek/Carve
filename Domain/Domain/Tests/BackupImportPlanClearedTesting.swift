//
//  BackupImportPlanClearedTesting.swift
//  DomainTest
//
//  불러오기 판정 — 비운 항목과 「비운 현재 + 잉크 보관」(설계 §5-1 「비운 대표 행」 · 예, §2-9 의 2절).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 백업에서 지운 절을 불러올 때 비운 현재 행을 건너뛰어, 같은 백업의 잉크 있는 보관 행이 대표로 올라가 **지운 필기가 되살아나는 것**
/// - 지금 필기가 있는 절을 백업의 비운 항목으로 비우거나, 기록에 빈 행을 더하는 것
/// - 같은 백업을 다시 불러올 때 비운 행 · 보관 행이 또 들어가는 것
@Suite("불러오기 판정 — 비운 항목")
struct BackupImportPlanClearedTesting {
    private typealias Sample = BackupImportPlanSample

    /// 지운 잉크 — 백업의 보관 행이 든다.
    private let erasedInk = Sample.ink("erased")

    /// (a) 비운 현재 행 — 9/30 에 지웠다. 좌표 형식 · 메타데이터는 남아 있다.
    private var clearedCurrent: BackupItem {
        Sample.item("A1F3C6E2-CLEARED", verse: 2, ink: nil, isCurrent: true, updatedAt: Sample.sep(30))
    }

    /// (b) 지운 잉크를 든 보관 행 — 9/25.
    private var archivedInk: BackupItem {
        Sample.item("D04B9A31-ARCHIVED", verse: 2, ink: erasedInk, isCurrent: false, updatedAt: Sample.sep(25))
    }

    @Test("빈 장 — 비운 행은 현재로, 잉크는 보관으로 넣고 대표는 비운 행이다")
    func emptyChapterKeepsTheClearedRowAsRepresentative() throws {
        // Given — 이 기기의 그 절에 행이 없다

        // When
        let plan = Sample.plan([clearedCurrent, archivedInk])

        // Then — 결정
        #expect(plan.decision(for: clearedCurrent.id) == .insertCurrent)
        #expect(plan.decision(for: archivedInk.id) == .insertArchived)
        // 넣을 행 — 비운 현재 행은 잉크 없이 present 이고 메타데이터는 남는다. 보관 행은 present 가 아니다.
        let cleared = try #require(plan.insertions.first { $0.itemID == clearedCurrent.id })
        #expect(cleared.isPresent)
        #expect(cleared.inkBlob == nil)
        #expect(cleared.fingerprint == nil)
        #expect(cleared.metadataBlob == clearedCurrent.metadataBlob)
        #expect(cleared.updateDate == Sample.sep(30))
        let archived = try #require(plan.insertions.first { $0.itemID == archivedInk.id })
        #expect(!archived.isPresent)
        #expect(archived.inkBlob == archivedInk.inkBlob)

        // Then — 넣은 뒤 대표는 비운 행이다: 절은 비어 보이고, 지운 필기는 「이전 필사 내용 보기」 에만 있다
        let stored = Sample.applying(plan, to: [], blobs: [erasedInk])
        let representative = try #require(Sample.representative(of: stored, verse: 2))
        #expect(representative.lineData == nil)
        #expect(representative.isPresent == true)
        #expect(stored.contains { $0.lineData == erasedInk && $0.isPresent == false })
        // 비운 행을 건너뛰었다면 — 대표 규칙은 isPresent 행이 없으면 전체에서 고르므로 지운 잉크가 대표가 됐다
        #expect(Sample.representative(of: stored.filter { $0.lineData != nil }, verse: 2)?.lineData == erasedInk)
    }

    @Test("잉크 있는 현재가 있는 장 — 비운 항목은 skipEmpty, 잉크는 보관으로")
    func inkedRepresentativeKeepsItsInk() throws {
        // Given — 9/28 의 잉크 있는 대표 X
        let current = [Sample.row("X", verse: 2, ink: Sample.ink("X"), isPresent: true, updatedAt: Sample.sep(28))]

        // When
        let plan = Sample.plan([clearedCurrent, archivedInk], current: current)

        // Then — 지금 필사를 비우지 않고, 지운 잉크는 기록에만 더한다
        #expect(plan.decision(for: clearedCurrent.id) == .skipEmpty)
        #expect(plan.decision(for: archivedInk.id) == .insertArchived)
        #expect(plan.insertions.map(\.itemID) == [archivedInk.id])
        let stored = Sample.applying(plan, to: current, blobs: [erasedInk])
        #expect(Sample.representative(of: stored, verse: 2)?.rowKey == "X")
    }

    @Test("이미 비운 대표가 있는 장 — 비운 항목은 skipSame, 잉크는 보관으로")
    func clearedRepresentativeStaysCleared() throws {
        // Given — 10/01 에 지운 절
        let current = [Sample.row("C", verse: 2, ink: nil, isPresent: true, updatedAt: Sample.oct(1))]

        // When
        let plan = Sample.plan([clearedCurrent, archivedInk], current: current)

        // Then
        #expect(plan.decision(for: clearedCurrent.id) == .skipSame)
        #expect(plan.decision(for: archivedInk.id) == .insertArchived)
        let stored = Sample.applying(plan, to: current, blobs: [erasedInk])
        #expect(Sample.representative(of: stored, verse: 2)?.rowKey == "C")
    }

    @Test("같은 백업을 다시 불러오면 넣을 행이 없다")
    func reimportAddsNothing() {
        // Given — 빈 장에 한 번 불러온 저장소
        let items = [clearedCurrent, archivedInk]
        let stored = Sample.applying(Sample.plan(items), to: [], blobs: [erasedInk])

        // When
        let again = Sample.plan(items, current: stored)

        // Then — 비운 행은 대표가 이미 비운 행이라, 보관 잉크는 같은 지문이 있어 건너뛴다
        #expect(again.insertions.isEmpty)
        #expect(again.decision(for: clearedCurrent.id) == .skipSame)
        #expect(again.decision(for: archivedInk.id) == .skipSame)
    }

    @Test("현재 후보가 아닌 비운 항목은 어느 절에도 넣지 않는다")
    func nonCandidateClearedItemIsNeverInserted() {
        // Given — 기록에 남아 있던 비운 행(현재 후보가 아니다)
        let oldCleared = Sample.item("OLD-CLEARED", verse: 2, ink: nil, isCurrent: false, updatedAt: Sample.sep(10))
        let inkedCurrent = [Sample.row("X", verse: 2, ink: Sample.ink("X"), isPresent: true, updatedAt: Sample.sep(28))]
        let clearedCurrentRow = [Sample.row("C", verse: 2, ink: nil, isPresent: true, updatedAt: Sample.oct(1))]

        // When · Then — 빈 절 · 잉크 있는 대표는 skipEmpty, 대표가 이미 비운 행이면 skipSame
        #expect(Sample.plan([oldCleared]).decision(for: oldCleared.id) == .skipEmpty)
        #expect(Sample.plan([oldCleared], current: inkedCurrent).decision(for: oldCleared.id) == .skipEmpty)
        #expect(Sample.plan([oldCleared], current: clearedCurrentRow).decision(for: oldCleared.id) == .skipSame)
        #expect(Sample.plan([oldCleared], current: clearedCurrentRow).insertions.isEmpty)
    }

    @Test("비운 현재 후보가 둘이면 늦은 하나만 비운 행으로 넣는다")
    func onlyOneClearedRowPerVerse() {
        // Given — 같은 절의 비운 현재 후보 둘(번역 nil 과 NKRV — 한 묶음이다)
        let later = Sample.item("LATER", verse: 2, ink: nil, isCurrent: true, updatedAt: Sample.sep(30))
        let earlier = Sample.item("EARLIER", verse: 2, ink: nil, isCurrent: true, updatedAt: Sample.sep(29), translation: nil)

        // When
        let plan = Sample.plan([earlier, later])

        // Then — 현재 후보만 비운 현재 행이 되고, 다른 하나는 현재 후보가 아니라 넣지 않는다
        #expect(plan.decision(for: later.id) == .insertCurrent)
        #expect(plan.decision(for: earlier.id) == .skipEmpty)
        #expect(plan.insertions.map(\.itemID) == [later.id])
    }

    @Test("비운 현재 후보는 잉크 있는 보관 행만 있는 절도 비우지 않는다")
    func clearedCandidateDoesNotClearAnInkedArchiveOnlyVerse() {
        // Given — isPresent 행이 없어 보관 잉크가 대표인 절(대표 규칙이 전체에서 고른다)
        let current = [Sample.row("ARCHIVE-ONLY", verse: 2, ink: Sample.ink("old"), isPresent: false, updatedAt: Sample.sep(5))]

        // When
        let plan = Sample.plan([clearedCurrent], current: current)

        // Then — 그 절에 행이 있으므로 비운 현재 행을 넣지 않는다(지금 보이는 필기를 비우지 않는다)
        #expect(plan.decision(for: clearedCurrent.id) == .skipEmpty)
        #expect(plan.insertions.isEmpty)
    }
}
