//
//  DrawingRepositoryTesting.swift
//  DomainTest
//
//  Phase 3 — 저장 계층 (설계 §8-6 원자적 batch · §8-7 행 주소지정과 결정적 대표 선택)
//  격리된 인메모리 컨테이너로 돈다 — 테스트끼리 공유 상태가 없다.
//

@testable import Domain
import Foundation
import PencilKit
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

// MARK: - UI-2 지우기 = 보관 후 초기화

/// `archiveAndReset` — 현재 필사를 보관 행으로 남기고 활성 행만 비운다. **삭제가 아니다.**
///
/// 고정하는 것은 넷이다.
/// 1. 보관 행은 내용을 그대로 복제하고 `isPresent = false` — 다시 대표로 뽑히지 않는다 (설계 §8-7 대표 규칙)
/// 2. 활성 행은 남아 비고 `isPresent = true` — 대표 자리를 지킨다
/// 3. 같은 명령을 다시 보내도 보관 행이 늘지 않는다 (재시도 안전)
/// 4. 이미 비어 있으면 아무것도 쓰지 않고, 다른 절도 건드리지 않는다
@Suite("UI-2 — DrawingRepository.archiveAndReset (보관 후 초기화)")
struct DrawingArchiveAndResetTesting {

    /// 실제 stroke 가 있는 `PKDrawing` 데이터. `containsPKStroke` 로 "비었는가" 를 판정하므로 임의 바이트로는 대신할 수 없다.
    private static func inkData(pointCount: Int = 8) -> Data {
        let points = (0..<pointCount).map { index in
            PKStrokePoint(
                location: CGPoint(x: Double(index) * 10, y: 0), timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        )
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    /// 활성 행 하나를 `create` 로 심고 그 rowID 를 돌려준다.
    private func seedActiveRow(
        _ harness: RepositoryHarness, verse: Int, data: Data
    ) async throws -> BibleDrawingRowID {
        let rowID = BibleDrawingRowID.issue()
        try await harness.repository.apply(
            [.create(verse: verse, rowID: rowID, data: data, metadata: harness.metadata(verse: verse))],
            chapter: harness.chapter
        )
        return rowID
    }

    @Test("보관 행은 내용을 복제하고 isPresent = false · 활성 행은 남아 비고 isPresent = true 로 대표를 지킨다")
    func archivesContentAndKeepsActiveRowAsEmptyRepresentative() async throws {
        let harness = try RepositoryHarness()
        let ink = Self.inkData()
        let activeRowID = try await seedActiveRow(harness, verse: 5, data: ink)
        let archiveRowID = BibleDrawingRowID.issue()
        let before = try await harness.rows(verse: 5).first?.updateDate

        let outcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 5, activeRowID: activeRowID, archiveRowID: archiveRowID),
            chapter: harness.chapter
        )

        #expect(outcome == .archived)
        let rows = try await harness.rows(verse: 5)
        // 아무것도 지우지 않는다 — 행이 하나 늘어난다.
        #expect(rows.count == 2)

        let archived = try #require(rows.first { $0.rowKey == archiveRowID.raw })
        #expect(archived.lineData == ink)
        #expect(archived.isPresent == false)
        #expect(archived.drawingVersion == 3)
        #expect(archived.layoutMetadataData != nil)
        // 기록 목록의 "필사 날짜" 는 원래 필사 시각이어야 한다.
        #expect(archived.updateDate == before)

        let active = try #require(rows.first { $0.rowKey == activeRowID.raw })
        #expect(active.lineData == nil)
        #expect(active.isPresent == true)

        // 대표 규칙이 빈 활성 행을 고른다 — 보관 행이 되살아나지 않는다 (§8-7).
        let snapshots = try await harness.actor.loadDrawingSnapshots(chapter: harness.chapter)
        let representative = try #require(snapshots.representativesByVerse()[5])
        #expect(representative.rowID == activeRowID)
        #expect(representative.lineData == nil)
        // 히스토리 목록에 쓰이는 조회에는 보관본이 그대로 있다.
        #expect(snapshots.filter { $0.verse == 5 }.compactMap(\.lineData) == [ink])
    }

    @Test("같은 명령을 다시 보내도 보관 행이 늘지 않는다 — 실패 후 재시도가 회차를 복제하지 않는다")
    func retryWithSameArchiveRowIDDoesNotDuplicate() async throws {
        let harness = try RepositoryHarness()
        let activeRowID = try await seedActiveRow(harness, verse: 6, data: Self.inkData())
        let command = VerseDrawingArchiveCommand(
            verse: 6, activeRowID: activeRowID, archiveRowID: BibleDrawingRowID.issue()
        )

        #expect(try await harness.repository.archiveAndReset(command, chapter: harness.chapter) == .archived)
        // 재시도 — 활성 행은 이미 비었으므로 쓸 것이 없다.
        #expect(try await harness.repository.archiveAndReset(command, chapter: harness.chapter) == .alreadyEmpty)

        let rows = try await harness.rows(verse: 6)
        #expect(rows.count == 2)
        #expect(rows.filter { $0.isPresent == true }.count == 1)
        #expect(rows.filter { $0.lineData != nil }.count == 1)
    }

    @Test("이미 비어 있으면 보관본을 만들지 않는다 — lineData 가 nil 이든 stroke 0개든")
    func alreadyEmptyVerseIsNotArchived() async throws {
        let harness = try RepositoryHarness()

        // ① `clear` 로 비워진 행.
        let cleared = try await seedActiveRow(harness, verse: 7, data: Self.inkData())
        try await harness.repository.apply([.clear(verse: 7, rowID: cleared)], chapter: harness.chapter)
        let clearedOutcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 7, activeRowID: cleared, archiveRowID: BibleDrawingRowID.issue()),
            chapter: harness.chapter
        )
        #expect(clearedOutcome == .alreadyEmpty)
        #expect(try await harness.rows(verse: 7).count == 1)

        // ② 획을 전부 지운 데이터(유효한 PKDrawing 이지만 stroke 0개)가 남아 있는 행.
        let emptyDrawing = try await seedActiveRow(harness, verse: 8, data: PKDrawing().dataRepresentation())
        let emptyOutcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 8, activeRowID: emptyDrawing, archiveRowID: BibleDrawingRowID.issue()),
            chapter: harness.chapter
        )
        #expect(emptyOutcome == .alreadyEmpty)
        #expect(try await harness.rows(verse: 8).count == 1)

        // ③ 행 자체가 없는 절 — 새 행을 만들지 않는다.
        let missingOutcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(
                verse: 9, activeRowID: BibleDrawingRowID(raw: "없는-행"), archiveRowID: BibleDrawingRowID.issue()
            ),
            chapter: harness.chapter
        )
        #expect(missingOutcome == .alreadyEmpty)
        #expect(try await harness.rows(verse: 9).isEmpty)
    }

    @Test("보관 행과 활성 행의 updateDate 가 같아도 빈 활성 행이 대표다 — 지운 획이 rowKey tie-break 로 되살아나지 않는다")
    func emptyActiveRowStaysRepresentativeOnDateTie() async throws {
        let harness = try RepositoryHarness()
        // legacy 행은 `isPresent` 표시가 없다 (D8 실측: 실기기 225행 전부 v1). 이 절의 유일한 행이므로 대표 규칙 ③ 으로 대표다.
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let activeKey = try await harness.seedLegacyRow(
            verse: 4, updateDate: stamp, isPresent: false, lineData: Self.inkData()
        )
        // 보관 행 키를 활성 행 키보다 사전순으로 **앞에** 둔다 — 동률이면 여기서 갈린다 (§8-7 tie-break).
        let archiveRowID = BibleDrawingRowID(raw: "0000-archive")
        #expect(archiveRowID.raw < activeKey)

        // 보관 시각을 활성 행의 필사 시각과 같게 만들어 `updateDate` 동률을 강제한다.
        let outcome = try await harness.actor.archiveAndResetVerseDrawing(
            VerseDrawingArchiveCommand(
                verse: 4, activeRowID: BibleDrawingRowID(raw: activeKey), archiveRowID: archiveRowID
            ),
            chapter: harness.chapter,
            now: stamp
        )
        #expect(outcome == .archived)

        // 날짜로도 rowKey 로도 보관 행이 이기는 배치다. 활성 행에 붙인 `isPresent` 만이 대표를 지킨다.
        let snapshots = try await harness.actor.loadDrawingSnapshots(chapter: harness.chapter)
        let representative = try #require(snapshots.representativesByVerse()[4])
        #expect(representative.rowID.raw == activeKey)
        #expect(representative.lineData == nil)
    }

    @Test("보관 rowID 에 행이 이미 있으면 덮어쓰고 present 표시를 떼어 낸다 — 재시도가 행을 늘리지도, 대표를 옮기지도 않는다")
    func upsertOntoExistingArchiveRowForcesNotPresent() async throws {
        let harness = try RepositoryHarness()
        let ink = Self.inkData()
        let activeRowID = try await seedActiveRow(harness, verse: 4, data: ink)
        let activeDate = try #require(try await harness.rows(verse: 4).first?.updateDate)

        // 보관 rowID 자리에 이미 행이 있고 present 표시까지 붙어 있는 상태 (동기화·이전 시도의 잔재).
        let archiveRowID = BibleDrawingRowID(raw: "이미-있는-보관행")
        let stale = BibleDrawing(
            bibleTitle: harness.chapter, verse: 4, lineData: nil,
            updateDate: Date(timeIntervalSince1970: 2_000_000_000), rowUUID: archiveRowID.raw
        )
        stale.isPresent = true
        try await harness.actor.insert(stale)

        _ = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 4, activeRowID: activeRowID, archiveRowID: archiveRowID),
            chapter: harness.chapter
        )

        let rows = try await harness.rows(verse: 4)
        #expect(rows.count == 2)   // 행이 늘지 않는다
        let archived = try #require(rows.first { $0.rowKey == archiveRowID.raw })
        #expect(archived.isPresent == false)
        #expect(archived.lineData == ink)
        #expect(archived.updateDate == activeDate)

        let snapshots = try await harness.actor.loadDrawingSnapshots(chapter: harness.chapter)
        #expect(snapshots.representativesByVerse()[4]?.rowID == activeRowID)
    }

    @Test("다른 절의 필사는 그대로 보존된다")
    func otherVersesAreUntouched() async throws {
        let harness = try RepositoryHarness()
        let target = try await seedActiveRow(harness, verse: 2, data: Self.inkData())
        let neighbourInk = Self.inkData(pointCount: 5)
        let neighbour = try await seedActiveRow(harness, verse: 3, data: neighbourInk)
        // 히스토리 회차가 있는 절도 함께 둔다.
        try await harness.seedLegacyRow(verse: 3, updateDate: Date(timeIntervalSince1970: 1_000), lineData: Self.inkData(pointCount: 3))

        _ = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 2, activeRowID: target, archiveRowID: BibleDrawingRowID.issue()),
            chapter: harness.chapter
        )

        let neighbourRows = try await harness.rows(verse: 3)
        #expect(neighbourRows.count == 2)
        #expect(neighbourRows.first { $0.rowKey == neighbour.raw }?.lineData == neighbourInk)
        #expect(neighbourRows.first { $0.rowKey == neighbour.raw }?.isPresent == true)
    }
}
