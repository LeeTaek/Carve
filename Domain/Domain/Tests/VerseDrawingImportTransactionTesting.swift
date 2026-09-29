//
//  VerseDrawingImportTransactionTesting.swift
//  DomainTest
//
//  「확인이 필요한 필기」 의 가져오기 — 저장소 한 트랜잭션과 초안에 남기는 가져온 기록 (2026-09-29).
//  격리된 인메모리 컨테이너 · 임시 보존 영역으로 돈다.
//

@testable import Domain
import Foundation
import PencilKit
import Testing

/// 실제 stroke 가 있는 `PKDrawing` 데이터 — 지금 필기가 이전 필사 기록으로 남는지(`hasStrokes`)를 보려면 임의 바이트로는 안 된다.
/// `offset` 이 다르면 다른 필기다.
///
/// **한 번만 만들어 재사용한다** — `dataRepresentation()` 은 같은 획이라도 부를 때마다 다른 바이트를 낸다(2026-09-29 확인). 두 번 만들면 지문이
/// 달라 같은 필기가 다른 필기로 비교된다.
func importInk(_ offset: Int) -> Data {
    importInks[offset]
}

private let importInks: [Data] = (0..<8).map { offset in
    let points = (0..<6).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index * 10 + offset), y: Double(offset)), timeOffset: Double(index) * 0.02,
            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    let stroke = PKStroke(
        ink: PKInk(.pen, color: .black),
        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    )
    return PKDrawing(strokes: [stroke]).dataRepresentation()
}

/// 이 파일이 막는 것:
/// - 가져오기가 **지금 필기를 지우거나 덮는 것** — 바꿔도 지금 필기는 그 행 그대로 이전 필사 기록에 남아야 한다
/// - 견준 뒤 그 절이 바뀌었는데도 쓰는 것, 견준 뒤 전체 삭제가 있었는데도 쓰는 것
/// - 같은 가져오기를 다시 보내 행이 늘어나는 것(저장 뒤 결과를 잃은 재시도)
/// - 가져오기를 모르고 열려 있던 화면이 옛 행에 이어 써 가져온 필기를 지우는 것
@Suite("가져오기 — 저장소 트랜잭션")
struct VerseDrawingImportTransactionTesting {

    private func command(
        _ harness: RepositoryHarness, verse: Int = 1, rowID: BibleDrawingRowID = .issue(), ink: Data?, expected: String?
    ) -> VerseDrawingImportCommand {
        VerseDrawingImportCommand(
            verse: verse, rowID: rowID, lineData: ink, metadata: ink == nil ? nil : harness.metadata(verse: verse), expectedCurrentFingerprint: expected
        )
    }

    private func seed(_ harness: RepositoryHarness, verse: Int = 1, ink: Data) async throws -> BibleDrawingRowID {
        let rowID = BibleDrawingRowID.issue()
        try await harness.apply([.create(verse: verse, rowID: rowID, data: ink, metadata: harness.metadata(verse: verse))], chapter: harness.chapter)
        return rowID
    }

    private func current(_ harness: RepositoryHarness, verse: Int = 1) async throws -> VerseDrawingSnapshot? {
        try await harness.load(chapter: harness.chapter).representativesByVerse()[verse]
    }

    private func generation(_ harness: RepositoryHarness) async throws -> DrawingStoreGeneration {
        try await harness.repository.load(chapter: harness.chapter).generation
    }

    @Test("빈 절에는 가져온 필기가 새 대표 행으로 들어간다 — v3 · 좌표 정보 · isPresent")
    func importsIntoAnEmptyVerse() async throws {
        let harness = try RepositoryHarness()
        let request = command(harness, ink: importInk(1), expected: nil)

        let outcome = try await harness.repository.importVerse(request, chapter: harness.chapter, generation: try await generation(harness))

        #expect(outcome == .imported(previousKept: false))
        let rows = try await harness.rows(verse: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.rowKey == request.rowID.raw)
        #expect(rows.first?.isPresent == true)
        #expect(rows.first?.drawingVersion == 3)
        #expect(rows.first?.lineData == importInk(1))
        #expect(DrawingLayoutMetadata.decode(blob: rows.first?.layoutMetadataData) == harness.metadata(verse: 1))
    }

    @Test("다른 필기가 있으면 새 행이 대표가 되고, 지금 필기는 그 행 그대로 대표에서 내려와 이전 필사 기록으로 남는다")
    func replaceKeepsThePreviousRowAsHistory() async throws {
        let harness = try RepositoryHarness()
        let previous = try await seed(harness, ink: importInk(1))
        let before = try #require(try await current(harness))
        let request = command(harness, ink: importInk(2), expected: before.contentFingerprint)

        let outcome = try await harness.repository.importVerse(request, chapter: harness.chapter, generation: try await generation(harness))

        #expect(outcome == .imported(previousKept: true))
        let snapshots = try await harness.load(chapter: harness.chapter)
        #expect(snapshots.count == 2)
        let kept = try #require(snapshots.first { $0.rowID == previous })
        #expect(kept.isPresent == false)
        #expect(kept.lineData == importInk(1))
        #expect(kept.updateDate == before.updateDate)
        #expect(try await current(harness)?.rowID == request.rowID)
        #expect(try await current(harness)?.lineData == importInk(2))
        // 「이전 필사 내용 보기」 는 두 필기를 모두 보인다.
        #expect(try await harness.rows(verse: 1).historyRows().count == 2)
    }

    @Test("견준 뒤 그 절의 필기가 바뀌었으면 아무것도 쓰지 않는다")
    func changedVerseIsNotWritten() async throws {
        let harness = try RepositoryHarness()
        let previous = try await seed(harness, ink: importInk(1))
        // 사용자는 빈 절이라고 보고 골랐다 — 그 사이 필기가 들어왔다.
        let request = command(harness, ink: importInk(2), expected: nil)

        let outcome = try await harness.repository.importVerse(request, chapter: harness.chapter, generation: try await generation(harness))

        #expect(outcome == .currentChanged)
        let rows = try await harness.rows(verse: 1)
        #expect(rows.map(\.rowKey) == [previous.raw])
        #expect(rows.first?.isPresent == true)
    }

    @Test("그 절이 이미 가져올 필기면 쓰지 않는다 — 같은 명령을 다시 보내도 행이 늘지 않는다")
    func sameContentIsNotWrittenTwice() async throws {
        let harness = try RepositoryHarness()
        _ = try await seed(harness, ink: importInk(1))
        let before = try #require(try await current(harness))
        let request = command(harness, ink: importInk(2), expected: before.contentFingerprint)
        let generation = try await generation(harness)

        #expect(try await harness.repository.importVerse(request, chapter: harness.chapter, generation: generation) == .imported(previousKept: true))
        // 저장 뒤 결과를 잃고 다시 보냈다.
        #expect(try await harness.repository.importVerse(request, chapter: harness.chapter, generation: generation) == .alreadyApplied)
        #expect(try await harness.rows(verse: 1).count == 2)

        // 다른 새 행으로 같은 내용을 가져와도 쓰지 않는다.
        let again = command(harness, ink: importInk(2), expected: before.contentFingerprint)
        #expect(try await harness.repository.importVerse(again, chapter: harness.chapter, generation: generation) == .alreadyApplied)
        #expect(try await harness.rows(verse: 1).count == 2)
    }

    @Test("견준 뒤 필사 데이터가 전부 지워졌으면 쓰지 않고 던진다")
    func staleGenerationIsRejected() async throws {
        let harness = try RepositoryHarness()
        let generation = try await generation(harness)
        try await harness.actor.eraseAllDrawingRows()

        await #expect(throws: DrawingRepositoryError.staleStoreGeneration) {
            try await harness.repository.importVerse(
                command(harness, ink: importInk(1), expected: nil), chapter: harness.chapter, generation: generation
            )
        }
        #expect(try await harness.rows(verse: 1).isEmpty)
    }

    @Test("가져오기를 모르는 화면이 옛 행에 이어 써도 가져온 필기가 대표로 남는다 — 그 획은 옛 행(이전 필사 기록)에 남는다")
    func staleCanvasWriteDoesNotEraseTheImport() async throws {
        let harness = try RepositoryHarness()
        let previous = try await seed(harness, ink: importInk(1))
        let before = try #require(try await current(harness))
        let request = command(harness, ink: importInk(2), expected: before.contentFingerprint)
        _ = try await harness.repository.importVerse(request, chapter: harness.chapter, generation: try await generation(harness))

        // 열려 있던 화면은 아직 옛 행을 대표로 알고 그 행에 획을 더해 저장한다.
        try await harness.apply([.replace(verse: 1, rowID: previous, data: importInk(3), metadata: harness.metadata(verse: 1))], chapter: harness.chapter)

        #expect(try await current(harness)?.rowID == request.rowID)
        #expect(try await current(harness)?.lineData == importInk(2))
        let history = try await harness.load(chapter: harness.chapter).first { $0.rowID == previous }
        #expect(history?.lineData == importInk(3))
        #expect(history?.isPresent == false)
    }
}

/// 초안에 남기는 가져온 기록 — **지우지 않는다**(ACC-1 F29 — 전송 전에 계정이 바뀌면 이 초안이 유일한 사본이다).
@Suite("가져오기 — 초안의 가져온 기록")
struct VerseDraftImportRecordTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let account = AccountScope(key: "acct-a")

    private func withWriter(_ body: (LocalPreservationWriter) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("import-record-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(LocalPreservationWriter(
            area: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        ))
    }

    private func draft(revision: Int, ink: String) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: "logged-out", chapter: chapter, verse: 1), revision: revision, rowID: BibleDrawingRowID(raw: "row-1"),
            lineData: Data(ink.utf8), drawingVersion: 3, layoutMetadataData: nil, base: .empty, baseFingerprint: nil, account: .localOnly,
            knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private var record: VerseDraftImport {
        VerseDraftImport(rowID: BibleDrawingRowID(raw: "row-imported"), contentFingerprint: "vc1-x", account: account,
                         importedAt: Date(timeIntervalSince1970: 5_000))
    }

    @Test("가져온 기록은 사용자가 본 revision 에만 남고 초안은 지우지 않는다 — 같은 revision 을 다시 써도 남고, 새 revision 은 가져오지 않은 내용이다")
    func recordFollowsTheRevision() async throws {
        try await withWriter { writer in
            _ = try await writer.saveDraft(draft(revision: 1, ink: "가"))

            // 그 사이 더 새 revision 이 쓰였다고 본 요청 — 남기지 않는다.
            #expect(try await writer.markDraftImported(draft(revision: 1, ink: "가").key, scope: .localOnly, revision: 2, record: record) == false)
            #expect(try await writer.drafts(in: .localOnly).first?.imported == nil)

            #expect(try await writer.markDraftImported(draft(revision: 1, ink: "가").key, scope: .localOnly, revision: 1, record: record))
            #expect(try await writer.drafts(in: .localOnly).map(\.imported) == [record])

            // 같은 revision · 같은 내용을 다시 써도(저장 재시도) 기록을 잃지 않는다.
            _ = try await writer.saveDraft(draft(revision: 1, ink: "가"))
            #expect(try await writer.drafts(in: .localOnly).map(\.imported) == [record])

            // 새 revision 은 가져오지 않은 내용이다.
            _ = try await writer.saveDraft(draft(revision: 2, ink: "나"))
            let latest = try await writer.drafts(in: .localOnly)
            #expect(latest.count == 1)
            #expect(latest.first?.revision == 2)
            #expect(latest.first?.imported == nil)
        }
    }
}
