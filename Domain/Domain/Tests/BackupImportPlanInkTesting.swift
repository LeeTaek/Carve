//
//  BackupImportPlanInkTesting.swift
//  DomainTest
//
//  불러오기 판정 — 잉크 있는 항목(설계 §5-1 ①~③): 빈 장 · 같은 내용 · 다른 현재 · 지운 절 보호 · 여러 현재 후보 · 파일 안 중복 · 번역 묶음.
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 지금 필사를 백업의 다른 내용으로 바꾸는 것 — 다른 내용은 이전 필사 기록에만 더한다
/// - 이 기기에서 백업보다 뒤에 지운 절을 백업의 필기로 되살리는 것
/// - 같은 내용을 두 번 넣는 것 — 같은 파일을 다시 불러와도, 한 파일 안에 같은 내용이 둘이어도
/// - 넣는 행의 시각 · 좌표 형식 · 메타데이터 · 번역 저장값을 바꾸는 것
@Suite("불러오기 판정 — 잉크 있는 항목")
struct BackupImportPlanInkTesting {
    private typealias Sample = BackupImportPlanSample

    @Test("빈 장 — 현재 후보는 현재로, 나머지는 보관으로 넣고 값은 원본 그대로다")
    func emptyChapterTakesTheBackupCurrent() throws {
        // Given — 초안(화면에 보이던 것, v3)과 1.3.0 의 v2 행(메타데이터 없음, 번역 저장값 없음)
        let shownInk = Sample.ink("shown-draft")
        let legacyInk = Sample.ink("legacy-v2")
        let shown = Sample.item("local|SESSION|NKRV|GEN|1|1|7", ink: shownInk, isCurrent: true, updatedAt: Sample.sep(20), kind: .draft)
        let legacy = Sample.item(
            "1-01Genesis.txt.1.1.1773450123", ink: legacyInk, isCurrent: false, updatedAt: Sample.sep(10),
            createdAt: Sample.sep(9), drawingVersion: 2, metadata: nil, translation: nil
        )

        // When
        let plan = Sample.plan([legacy, shown])

        // Then — 결정
        #expect(plan.decision(for: shown.id) == .insertCurrent)
        #expect(plan.decision(for: legacy.id) == .insertArchived)
        // 넣을 행 — 처리 순서(현재 후보 먼저)이고 값은 항목 원본 그대로다
        #expect(plan.insertions.map(\.itemID) == [shown.id, legacy.id])
        let current = try #require(plan.insertions.first)
        #expect(current.isPresent)
        #expect(current.titleName == BibleTitle.genesis.rawValue)
        #expect(current.chapter == Sample.chapter)
        #expect(current.verse == 1)
        #expect(current.translation == "NKRV")
        #expect(current.drawingVersion == 3)
        #expect(current.inkBlob == shown.inkBlob)
        #expect(current.metadataBlob == shown.metadataBlob)
        #expect(current.fingerprint == shown.fingerprint)
        #expect(current.creationDate == nil)
        #expect(current.updateDate == Sample.sep(20))
        let archived = try #require(plan.insertions.last)
        #expect(!archived.isPresent)
        #expect(archived.translation == nil)
        #expect(archived.drawingVersion == 2)
        #expect(archived.metadataBlob == nil)
        #expect(archived.creationDate == Sample.sep(9))
        #expect(archived.updateDate == Sample.sep(10))

        // Then — 넣은 뒤 대표는 현재 후보다
        let stored = Sample.applying(plan, to: [], blobs: [shownInk, legacyInk])
        #expect(Sample.representative(of: stored)?.lineData == shownInk)
    }

    @Test("같은 내용 — 대표 · 보관 행과 지문이 같으면 skipSame, 좌표 형식이 다르면 다른 내용이다")
    func sameContentIsSkipped() {
        // Given — 대표 X 와 보관 W 가 있는 절
        let inkX = Sample.ink("X")
        let inkW = Sample.ink("W")
        let current = [
            Sample.row("X", ink: inkX, isPresent: true, updatedAt: Sample.sep(20)),
            Sample.row("W", ink: inkW, isPresent: false, updatedAt: Sample.sep(10))
        ]
        let sameAsX = Sample.item("OTHER-DEVICE-X", ink: inkX, isCurrent: true, updatedAt: Sample.sep(21))
        let sameAsW = Sample.item("OTHER-DEVICE-W", ink: inkW, isCurrent: false, updatedAt: Sample.sep(11))
        let otherVersion = Sample.item("X-AS-V2", ink: inkX, isCurrent: false, updatedAt: Sample.sep(5), drawingVersion: 2, metadata: nil)

        // When
        let plan = Sample.plan([sameAsX, sameAsW, otherVersion], current: current)

        // Then — 다른 기기 · 다른 백업이 담아 id 가 달라도 지문으로 견준다
        #expect(plan.decision(for: sameAsX.id) == .skipSame)
        #expect(plan.decision(for: sameAsW.id) == .skipSame)
        #expect(plan.decision(for: otherVersion.id) == .insertArchived)
        #expect(plan.insertions.map(\.itemID) == [otherVersion.id])
    }

    @Test("같은 백업을 다시 불러오면 넣을 행이 없다")
    func reimportAddsNothing() {
        // Given — 빈 장에 한 번 불러온 저장소
        let inkY = Sample.ink("Y")
        let inkZ = Sample.ink("Z")
        let items = [
            Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20)),
            Sample.item("Z", ink: inkZ, isCurrent: false, updatedAt: Sample.sep(10))
        ]
        let stored = Sample.applying(Sample.plan(items), to: [], blobs: [inkY, inkZ])

        // When
        let again = Sample.plan(items, current: stored)

        // Then
        #expect(again.insertions.isEmpty)
        #expect(again.decisions.allSatisfy { $0.decision == .skipSame })
    }

    @Test("다른 현재 — 잉크 있는 대표가 있으면 백업의 현재 필기는 보관으로만")
    func differentCurrentIsArchived() {
        // Given — 9/28 의 대표 X. 백업의 현재 필기 Y 가 더 늦어도 지금 필사를 바꾸지 않는다
        let current = [Sample.row("X", ink: Sample.ink("X"), isPresent: true, updatedAt: Sample.sep(28))]
        let inkY = Sample.ink("Y")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(30))

        // When
        let plan = Sample.plan([backupCurrent], current: current)

        // Then
        #expect(plan.decision(for: backupCurrent.id) == .insertArchived)
        #expect(plan.insertions.first?.isPresent == false)
        let stored = Sample.applying(plan, to: current, blobs: [inkY])
        #expect(Sample.representative(of: stored)?.rowKey == "X")
    }

    @Test("비운 대표가 더 늦으면 protectCleared — 지운 절을 되살리지 않고 기록에만 둔다")
    func laterClearedRepresentativeIsProtected() throws {
        // Given — 9/29 에 지운 절(보관 행 하나). 백업의 현재 필기 Y 는 9/20
        let current = [
            Sample.row("C", ink: nil, isPresent: true, updatedAt: Sample.sep(29)),
            Sample.row("OLD", ink: Sample.ink("old"), isPresent: false, updatedAt: Sample.sep(15))
        ]
        let inkY = Sample.ink("Y")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20))

        // When
        let plan = Sample.plan([backupCurrent], current: current)

        // Then
        #expect(plan.decision(for: backupCurrent.id) == .protectCleared)
        let protected = try #require(plan.insertions.first)
        #expect(!protected.isPresent)
        #expect(protected.updateDate == Sample.sep(20))
        let stored = Sample.applying(plan, to: current, blobs: [inkY])
        #expect(Sample.representative(of: stored)?.rowKey == "C")
    }

    @Test("비운 대표가 더 이르면 insertCurrent — 백업의 필기가 대표가 된다")
    func earlierClearedRepresentativeGivesWay() {
        // Given — 9/10 에 지운 절. 백업의 현재 필기 Y 는 9/20
        let current = [Sample.row("C", ink: nil, isPresent: true, updatedAt: Sample.sep(10))]
        let inkY = Sample.ink("Y")
        let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20))

        // When
        let plan = Sample.plan([backupCurrent], current: current)

        // Then
        #expect(plan.decision(for: backupCurrent.id) == .insertCurrent)
        let stored = Sample.applying(plan, to: current, blobs: [inkY])
        #expect(Sample.representative(of: stored)?.lineData == inkY)
    }

    @Test("지운 절 보호는 더 늦을 때만이고, 시각 nil 은 가장 이른 시각이다")
    func clearTimeBoundaries() {
        let inkY = Sample.ink("Y")
        func decision(clearedAt: Date?, writtenAt: Date?) -> BackupImportDecision? {
            let backupCurrent = Sample.item("Y", ink: inkY, isCurrent: true, updatedAt: writtenAt)
            let current = [Sample.row("C", ink: nil, isPresent: true, updatedAt: clearedAt)]
            return Sample.plan([backupCurrent], current: current).decision(for: backupCurrent.id)
        }

        // 같은 시각 — 늦지 않으므로 보호하지 않는다
        #expect(decision(clearedAt: Sample.sep(20), writtenAt: Sample.sep(20)) == .insertCurrent)
        // 지운 시각을 모른다 — 가장 이른 시각이라 보호하지 않는다
        #expect(decision(clearedAt: nil, writtenAt: Sample.sep(20)) == .insertCurrent)
        // 쓴 시각을 모른다 — 가장 이른 시각이라 지운 것이 더 늦다
        #expect(decision(clearedAt: Sample.sep(1), writtenAt: nil) == .protectCleared)
        #expect(decision(clearedAt: nil, writtenAt: nil) == .insertCurrent)
    }

    @Test("현재 후보가 여럿이면 updatedAt 이 가장 늦은 하나만 현재로, 나머지는 보관으로")
    func latestCurrentCandidateWins() {
        // Given — 같은 절의 현재 항목 셋(번역 nil 과 NKRV 는 한 묶음이다)
        let inkEarly = Sample.ink("early")
        let inkLate = Sample.ink("late")
        let inkUnknownTime = Sample.ink("unknown-time")
        let early = Sample.item("EARLY", ink: inkEarly, isCurrent: true, updatedAt: Sample.sep(20))
        let late = Sample.item("LATE", ink: inkLate, isCurrent: true, updatedAt: Sample.sep(25), translation: nil)
        let unknownTime = Sample.item("UNKNOWN-TIME", ink: inkUnknownTime, isCurrent: true, updatedAt: nil)

        // When
        let plan = Sample.plan([early, unknownTime, late])

        // Then
        #expect(plan.decision(for: late.id) == .insertCurrent)
        #expect(plan.decision(for: early.id) == .insertArchived)
        #expect(plan.decision(for: unknownTime.id) == .insertArchived)
        #expect(plan.insertions.filter(\.isPresent).map(\.itemID) == [late.id])
        let stored = Sample.applying(plan, to: [], blobs: [inkEarly, inkLate, inkUnknownTime])
        #expect(Sample.representative(of: stored)?.lineData == inkLate)
    }

    @Test("현재 후보의 updatedAt 이 같으면 id 사전순 앞이 현재다")
    func currentCandidateTieBreaksByID() {
        // Given — 같은 시각의 현재 항목 둘. id 를 거꾸로 넘긴다
        let first = Sample.item("FIRST", ink: Sample.ink("first"), isCurrent: true, updatedAt: Sample.sep(20), id: "row-0001")
        let second = Sample.item("SECOND", ink: Sample.ink("second"), isCurrent: true, updatedAt: Sample.sep(20), id: "row-0002")

        // When
        let plan = Sample.plan([second, first])

        // Then
        #expect(plan.decision(for: first.id) == .insertCurrent)
        #expect(plan.decision(for: second.id) == .insertArchived)
    }

    @Test("파일 안 같은 지문 — 한 절에 한 번만 넣고, 현재 후보가 먼저다")
    func duplicateFingerprintsAreInsertedOncePerVerse() {
        // Given — 같은 잉크를 담은 항목(다른 행 키라 id 가 다르다). 현재 후보의 id 가 사전순으로 뒤다
        let ink = Sample.ink("same")
        let archivedCopy = Sample.item("COPY", ink: ink, isCurrent: false, updatedAt: Sample.sep(10), id: "row-0001")
        let currentCopy = Sample.item("CURRENT", ink: ink, isCurrent: true, updatedAt: Sample.sep(20), id: "row-0009")
        let archivedOther = Sample.item("OTHER-1", ink: Sample.ink("other"), isCurrent: false, updatedAt: Sample.sep(5), id: "row-0003")
        let archivedOtherCopy = Sample.item("OTHER-2", ink: Sample.ink("other"), isCurrent: false, updatedAt: Sample.sep(6), id: "row-0004")
        // 다른 절의 같은 잉크는 그 절에서 따로 넣는다
        let otherVerse = Sample.item("VERSE-2", verse: 2, ink: ink, isCurrent: true, updatedAt: Sample.sep(20))

        // When
        let plan = Sample.plan([archivedCopy, archivedOtherCopy, otherVerse, currentCopy, archivedOther])

        // Then
        #expect(plan.decision(for: currentCopy.id) == .insertCurrent)
        #expect(plan.decision(for: archivedCopy.id) == .skipSame)
        #expect(plan.decision(for: archivedOther.id) == .insertArchived)
        #expect(plan.decision(for: archivedOtherCopy.id) == .skipSame)
        #expect(plan.decision(for: otherVerse.id) == .insertCurrent)
        #expect(plan.insertions.map(\.itemID) == [currentCopy.id, archivedOther.id, otherVerse.id])
    }

    @Test("번역 nil 은 NKRV 와 한 묶음으로 판정하고, 저장값은 nil 그대로 넣는다")
    func nilTranslationGroupsWithNKRV() throws {
        let inkX = Sample.ink("X")
        let inkY = Sample.ink("Y")

        // 번역 nil 인 지금 행과 NKRV 항목 — 같은 내용이다
        let nilRow = [Sample.row("X-NIL", ink: inkX, isPresent: true, updatedAt: Sample.sep(10), translation: nil)]
        let nkrvItem = Sample.item("X-NKRV", ink: inkX, isCurrent: true, updatedAt: Sample.sep(10))
        #expect(Sample.plan([nkrvItem], current: nilRow).decision(for: nkrvItem.id) == .skipSame)

        // NKRV 대표가 있는 절의 번역 nil 현재 항목 — 같은 절이라 보관으로만, 저장값은 nil
        let nkrvRow = [Sample.row("X", ink: inkX, isPresent: true, updatedAt: Sample.sep(10))]
        let nilItem = Sample.item("Y-NIL", ink: inkY, isCurrent: true, updatedAt: Sample.sep(20), translation: nil)
        let archivedPlan = Sample.plan([nilItem], current: nkrvRow)
        #expect(archivedPlan.decision(for: nilItem.id) == .insertArchived)
        let archivedRow = try #require(archivedPlan.insertions.first)
        #expect(archivedRow.translation == nil)

        // 빈 절이면 현재로 — 저장값은 nil 그대로
        let currentPlan = Sample.plan([nilItem])
        #expect(currentPlan.decision(for: nilItem.id) == .insertCurrent)
        let currentRow = try #require(currentPlan.insertions.first)
        #expect(currentRow.translation == nil)
    }

    @Test("다른 장의 항목 · 행은 이 장 판정에 들지 않는다")
    func otherChaptersAreNotJudged() {
        // Given — 창세기 2장 항목과, 창세기 1장 항목과 같은 내용을 든 창세기 2장 행
        let ink = Sample.ink("Y")
        let genesis1 = Sample.item("GEN1", ink: ink, isCurrent: true, updatedAt: Sample.sep(20))
        let genesis2 = Sample.item("GEN2", ink: Sample.ink("Z"), isCurrent: true, updatedAt: Sample.sep(20), chapter: 2)
        let exodus1 = Sample.item("EXO1", ink: Sample.ink("E"), isCurrent: true, updatedAt: Sample.sep(20), book: "EXO")
        let otherChapterRow = Sample.row("GEN2-ROW", ink: ink, isPresent: true, updatedAt: Sample.sep(20), chapter: 2)

        // When
        let plan = Sample.plan([genesis1, genesis2, exodus1], current: [otherChapterRow])

        // Then — 창세기 1장 항목만 판정하고, 2장 행은 견주지 않는다
        #expect(plan.decisions.map(\.itemID) == [genesis1.id])
        #expect(plan.decision(for: genesis1.id) == .insertCurrent)
        #expect(plan.decision(for: genesis2.id) == nil)
        #expect(plan.decision(for: exodus1.id) == nil)
    }
}
