//
//  DrawingRepositoryTesting.swift
//  DomainTest
//
//  Phase 3 — 저장 계층 (설계 §8-6 원자적 batch · §8-7 행 주소지정과 결정적 대표 선택)
//  격리된 인메모리 컨테이너로 돈다 — 테스트끼리 공유 상태가 없다.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

// MARK: - 하네스

/// 테스트마다 새 인메모리 컨테이너 + actor + repository.
struct RepositoryHarness {
    let actor: SwiftDatabaseActor
    let repository: SwiftDataDrawingRepository
    let chapter = BibleChapter(title: .habakkuk, chapter: 3)

    init() throws {
        let container = try ModelContainer(
            for: Schema([BibleDrawing.self, BiblePageDrawing.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        actor = SwiftDatabaseActor(modelContainer: container)
        repository = SwiftDataDrawingRepository(actor: actor)
    }

    func metadata(verse: Int, anchors: [CGFloat] = [0, 30]) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: 372,
            baseWritingHeight: 60,
            baseUnderlineAnchors: anchors,
            layoutSignature: "cl1-test-\(verse)"
        )
    }

    /// legacy 행(rowUUID 없음, drawingVersion 1)을 심는다. business id 가 행 키다.
    ///
    /// business id 는 `"<권>.<장>.<절>.<초>"` 라 같은 초에 만든 두 행이 **같은 id** 를 갖는다 (§8-7 이 지적한 충돌).
    /// 테스트가 그 충돌에 걸리지 않도록 `updateDate` 의 초를 id 에 쓴다.
    @discardableResult
    func seedLegacyRow(verse: Int, updateDate: Date, isPresent: Bool = false, lineData: Data? = Data([1, 2, 3])) async throws -> String {
        let row = BibleDrawing(bibleTitle: chapter, verse: verse, lineData: lineData, updateDate: updateDate, rowUUID: nil)
        row.id = "\(chapter.title.rawValue).\(chapter.chapter).\(verse).\(Int(updateDate.timeIntervalSince1970))"
        row.isPresent = isPresent
        row.drawingVersion = 1
        try await actor.insert(row)
        return row.rowKey
    }

    func rows(verse: Int) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber && $0.verse == verse
        }
        return try await actor.fetch(FetchDescriptor(predicate: predicate))
    }
}

// MARK: - §8-6 · §8-7

@Suite("Phase 3 — DrawingRepository (SwiftData)")
struct DrawingRepositoryTesting {

    @Test("create 는 선발급 rowID 를 rowUUID 로 쓰고 drawingVersion 3 · isPresent · metadata 를 기록한다")
    func createUsesIssuedRowIDAndMarksVersion3() async throws {
        let harness = try RepositoryHarness()
        let rowID = BibleDrawingRowID.issue()
        let metadata = harness.metadata(verse: 4)

        try await harness.repository.apply(
            [.create(verse: 4, rowID: rowID, data: Data([9, 9]), metadata: metadata)],
            chapter: harness.chapter
        )

        let rows = try await harness.rows(verse: 4)
        #expect(rows.count == 1)
        #expect(rows.first?.rowUUID == rowID.raw)
        #expect(rows.first?.drawingVersion == 3)
        #expect(rows.first?.isPresent == true)
        #expect(rows.first?.lineData == Data([9, 9]))
        #expect(DrawingLayoutMetadata.decode(blob: rows.first?.layoutMetadataData) == metadata)

        let loaded = try await harness.repository.load(chapter: harness.chapter)
        #expect(loaded.count == 1)
        #expect(loaded.first?.rowID == rowID)
        #expect(loaded.first?.hasVersionedLayout == true)
        #expect(loaded.first?.metadata == metadata)
    }

    @Test("legacy 행은 business id 로 주소지정되고, replace 가 drawingVersion 을 3 으로 승격한다 (§10-2 정책 5)")
    func replaceAddressesLegacyRowByBusinessIDAndPromotes() async throws {
        let harness = try RepositoryHarness()
        let key = try await harness.seedLegacyRow(verse: 2, updateDate: Date(timeIntervalSince1970: 1_000))
        let rowID = BibleDrawingRowID(raw: key)
        let metadata = harness.metadata(verse: 2)

        try await harness.repository.apply(
            [.replace(verse: 2, rowID: rowID, data: Data([7]), metadata: metadata)],
            chapter: harness.chapter
        )

        let rows = try await harness.rows(verse: 2)
        #expect(rows.count == 1)
        #expect(rows.first?.rowUUID == nil)                 // legacy 행에 rowUUID 를 소급 발급하지 않는다
        #expect(rows.first?.lineData == Data([7]))
        #expect(rows.first?.drawingVersion == 3)
        #expect(rows.first?.updateDate ?? .distantPast > Date(timeIntervalSince1970: 1_000))

        let loaded = try await harness.repository.load(chapter: harness.chapter)
        #expect(loaded.first?.rowID == rowID)
    }

    @Test("clear 는 행을 삭제하지 않고 lineData 만 비운다 — 과거 회차가 승격되지 않는다 (§14 5)")
    func clearKeepsRowSoOlderRevisionIsNotPromoted() async throws {
        let harness = try RepositoryHarness()
        let older = try await harness.seedLegacyRow(verse: 5, updateDate: Date(timeIntervalSince1970: 100), lineData: Data([1]))
        let newer = try await harness.seedLegacyRow(verse: 5, updateDate: Date(timeIntervalSince1970: 200), isPresent: true, lineData: Data([2]))

        try await harness.repository.apply([.clear(verse: 5, rowID: BibleDrawingRowID(raw: newer))], chapter: harness.chapter)

        let loaded = try await harness.repository.load(chapter: harness.chapter)
        #expect(loaded.count == 2)
        let cleared = try #require(loaded.first { $0.rowID.raw == newer })
        #expect(cleared.lineData == nil)
        #expect(cleared.isPresent)
        // 대표는 여전히 비워진 행이다 — 옛 회차(older)가 되살아나지 않는다.
        #expect(loaded.representative()?.rowID.raw == newer)
        #expect(loaded.first { $0.rowID.raw == older }?.lineData == Data([1]))
    }

    @Test("batch 중 하나가 실패하면 전부 롤백된다 (§14 3 · P8)")
    func batchIsAtomic() async throws {
        let harness = try RepositoryHarness()
        let existing = try await harness.seedLegacyRow(verse: 1, updateDate: Date(timeIntervalSince1970: 1), lineData: Data([1]))
        let missing = BibleDrawingRowID(raw: "no-such-row")

        await #expect(throws: DrawingRepositoryError.rowNotFound(missing)) {
            try await harness.repository.apply(
                [
                    .replace(verse: 1, rowID: BibleDrawingRowID(raw: existing), data: Data([42]), metadata: harness.metadata(verse: 1)),
                    .create(verse: 2, rowID: BibleDrawingRowID.issue(), data: Data([2]), metadata: harness.metadata(verse: 2)),
                    .replace(verse: 3, rowID: missing, data: Data([3]), metadata: harness.metadata(verse: 3))
                ],
                chapter: harness.chapter
            )
        }

        // 첫 replace 와 create 도 적용되지 않았다.
        let loaded = try await harness.repository.load(chapter: harness.chapter)
        #expect(loaded.count == 1)
        #expect(loaded.first?.lineData == Data([1]))
        #expect(loaded.first?.drawingVersion == 1)
        #expect(try await harness.rows(verse: 2).isEmpty)
    }

    @Test("같은 rowID 의 create 가 다시 오면 행을 늘리지 않고 갱신한다 — upsert (§8-7)")
    func createIsUpsertByRowID() async throws {
        let harness = try RepositoryHarness()
        let rowID = BibleDrawingRowID.issue()
        try await harness.repository.apply(
            [.create(verse: 1, rowID: rowID, data: Data([1]), metadata: harness.metadata(verse: 1))],
            chapter: harness.chapter
        )
        try await harness.repository.apply(
            [.create(verse: 1, rowID: rowID, data: Data([2]), metadata: harness.metadata(verse: 1, anchors: [0, 30, 60]))],
            chapter: harness.chapter
        )

        let rows = try await harness.rows(verse: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.lineData == Data([2]))
        #expect(DrawingLayoutMetadata.decode(blob: rows.first?.layoutMetadataData)?.savedBandCount == 3)
    }

    @Test("clear 가 가리킨 행이 없으면 빈 행을 만든다 — 앞선 create 의 저장 여부와 무관하게 결과가 같다")
    func clearOnMissingRowCreatesEmptyRow() async throws {
        let harness = try RepositoryHarness()
        let rowID = BibleDrawingRowID.issue()

        try await harness.repository.apply([.clear(verse: 6, rowID: rowID)], chapter: harness.chapter)

        let rows = try await harness.rows(verse: 6)
        #expect(rows.count == 1)
        #expect(rows.first?.rowUUID == rowID.raw)
        #expect(rows.first?.lineData == nil)
        #expect(rows.first?.drawingVersion == 3)
        #expect(rows.first?.isPresent == true)
    }

    @Test("replace 가 가리킨 행이 없으면 rowNotFound — 주소지정 버그를 새 행으로 바꾸지 않는다")
    func replaceOnMissingRowFails() async throws {
        let harness = try RepositoryHarness()
        let missing = BibleDrawingRowID.issue()

        await #expect(throws: DrawingRepositoryError.rowNotFound(missing)) {
            try await harness.repository.apply(
                [.replace(verse: 1, rowID: missing, data: Data([1]), metadata: harness.metadata(verse: 1))],
                chapter: harness.chapter
            )
        }
        #expect(try await harness.rows(verse: 1).isEmpty)
    }

    @Test("다른 장의 같은 절 행은 건드리지 않는다")
    func mutationsAreScopedToChapter() async throws {
        let harness = try RepositoryHarness()
        let other = BibleChapter(title: .habakkuk, chapter: 2)
        let foreign = BibleDrawing(bibleTitle: other, verse: 1, lineData: Data([5]), rowUUID: "shared-key")
        try await harness.actor.insert(foreign)
        let sharedID = BibleDrawingRowID(raw: "shared-key")

        // replace 는 엄격하다 — 다른 장의 행은 보이지 않으므로 rowNotFound.
        await #expect(throws: DrawingRepositoryError.rowNotFound(sharedID)) {
            try await harness.repository.apply(
                [.replace(verse: 1, rowID: sharedID, data: Data([1]), metadata: harness.metadata(verse: 1))],
                chapter: harness.chapter
            )
        }
        // clear 는 이 장에 빈 행을 만들 뿐, 다른 장의 행을 비우지 않는다.
        try await harness.repository.apply([.clear(verse: 1, rowID: sharedID)], chapter: harness.chapter)

        #expect(try await harness.repository.load(chapter: other).first?.lineData == Data([5]))
        let mine = try await harness.repository.load(chapter: harness.chapter)
        #expect(mine.count == 1)
        #expect(mine.first?.lineData == nil)
        #expect(mine.first?.rowID == sharedID)
    }

    @Test("load 는 절 → 행 키 순으로 정렬돼 삽입 순서와 무관하다")
    func loadIsSortedDeterministically() async throws {
        let harness = try RepositoryHarness()
        try await harness.repository.apply(
            [
                .create(verse: 3, rowID: BibleDrawingRowID(raw: "b"), data: Data([3]), metadata: harness.metadata(verse: 3)),
                .create(verse: 1, rowID: BibleDrawingRowID(raw: "z"), data: Data([1]), metadata: harness.metadata(verse: 1)),
                .create(verse: 3, rowID: BibleDrawingRowID(raw: "a"), data: Data([3]), metadata: harness.metadata(verse: 3))
            ],
            chapter: harness.chapter
        )

        let loaded = try await harness.repository.load(chapter: harness.chapter)
        #expect(loaded.map { "\($0.verse)/\($0.rowID.raw)" } == ["1/z", "3/a", "3/b"])
    }
}

// MARK: - §8-7 결정적 대표 선택

@Suite("Phase 3 — 대표 행 선택 규칙")
struct DrawingRepresentativeRuleTesting {
    private func snapshot(_ key: String, verse: Int = 1, isPresent: Bool, date: TimeInterval?) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse,
            rowID: BibleDrawingRowID(raw: key),
            isPresent: isPresent,
            updateDate: date.map { Date(timeIntervalSince1970: $0) },
            lineData: nil,
            drawingVersion: 1,
            metadata: nil
        )
    }

    @Test("isPresent 행이 여럿이면 updateDate 최신, 동률이면 rowID 사전순 — 입력 순서와 무관 (§14 5-4)")
    func multiplePresentRowsResolveDeterministically() {
        let rows = [
            snapshot("c", isPresent: true, date: 200),
            snapshot("a", isPresent: true, date: 200),
            snapshot("b", isPresent: true, date: 100),
            snapshot("z", isPresent: false, date: 900)
        ]
        #expect(rows.representative()?.rowID.raw == "a")
        #expect(rows.reversed().representative()?.rowID.raw == "a")
        #expect(rows.shuffled().representative()?.rowID.raw == "a")
    }

    @Test("isPresent 행이 없으면 updateDate 최신 → 동률이면 rowID 사전순, updateDate nil 은 가장 오래된 것으로 본다")
    func fallsBackToLatestUpdateDate() {
        let rows = [
            snapshot("n", isPresent: false, date: nil),
            snapshot("y", isPresent: false, date: 300),
            snapshot("x", isPresent: false, date: 300)
        ]
        #expect(rows.representative()?.rowID.raw == "x")
        #expect([snapshot("only", isPresent: false, date: nil)].representative()?.rowID.raw == "only")
        #expect([VerseDrawingSnapshot]().representative() == nil)
    }

    @Test("representativesByVerse 는 절마다 하나씩 고른다")
    func representativesPerVerse() {
        let rows = [
            snapshot("a1", verse: 1, isPresent: true, date: 1),
            snapshot("a2", verse: 1, isPresent: false, date: 5),
            snapshot("b1", verse: 2, isPresent: false, date: 1),
            snapshot("b2", verse: 2, isPresent: false, date: 2)
        ]
        let byVerse = rows.representativesByVerse()
        #expect(byVerse[1]?.rowID.raw == "a1")
        #expect(byVerse[2]?.rowID.raw == "b2")
        #expect(byVerse.count == 2)
    }

    @Test("모델의 mainDrawing() 도 같은 규칙을 쓴다")
    func modelMainDrawingUsesSameRule() {
        let chapter = BibleChapter(title: .genesis, chapter: 1)
        let first = BibleDrawing(bibleTitle: chapter, verse: 1, updateDate: Date(timeIntervalSince1970: 50), rowUUID: "b")
        first.isPresent = true
        let second = BibleDrawing(bibleTitle: chapter, verse: 1, updateDate: Date(timeIntervalSince1970: 50), rowUUID: "a")
        second.isPresent = true
        let third = BibleDrawing(bibleTitle: chapter, verse: 1, updateDate: Date(timeIntervalSince1970: 999), rowUUID: "c")

        #expect([first, second, third].mainDrawing()?.rowUUID == "a")
        #expect([third, first, second].mainDrawing()?.rowUUID == "a")
        #expect([third].mainDrawing()?.rowUUID == "c")
    }
}
