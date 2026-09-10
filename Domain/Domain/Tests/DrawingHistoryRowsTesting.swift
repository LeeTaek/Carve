//
//  DrawingHistoryRowsTesting.swift
//  DomainTest
//
//  UI-2 후속 — "빈 행은 **히스토리 목록에서만** 숨긴다" (설계 §8-7).
//
//  지우기는 활성 행을 비우고 `updateDate` 를 `now` 로 찍으므로, 거르지 않으면 목록 **맨 위**에
//  내용 없는 행이 온다. 그렇다고 조회·대표 선택에서 걸러내면 과거 회차가 승격돼 **지운 획이 되살아난다.**
//  두 방향을 한 테스트에서 함께 고정한다.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import Dependencies

@Suite("§8-7 — 히스토리 목록의 빈 행 숨김")
struct DrawingHistoryRowsTesting {
    private static let chapter = BibleChapter(title: .habakkuk, chapter: 3)
    private static let verse = 4

    /// 인메모리 컨테이너 하나에 actor 와 `DrawingDatabase` 를 함께 물린다.
    ///
    /// 목록이 실제로 쓰는 조회(`DrawingDatabase.fetchDrawings(chapter:verse:)`)와 지우기
    /// (`archiveAndResetVerseDrawing`)가 **같은 저장소**를 봐야 두 경로의 어긋남을 잡을 수 있다.
    private struct Harness {
        let actor: SwiftDatabaseActor
        let database: DrawingDatabase

        init() throws {
            let container = try ModelContainer(
                for: Schema([BibleDrawing.self, BiblePageDrawing.self]),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let actor = SwiftDatabaseActor(modelContainer: container)
            self.actor = actor
            self.database = withDependencies {
                $0.createSwiftDataActor = actor
            } operation: {
                DrawingDatabase()
            }
        }

        @discardableResult
        func seed(rowID: BibleDrawingRowID, lineData: Data?, updateDate: Date, isPresent: Bool = false) async throws -> BibleDrawing {
            let row = BibleDrawing(
                bibleTitle: DrawingHistoryRowsTesting.chapter,
                verse: DrawingHistoryRowsTesting.verse,
                lineData: lineData,
                updateDate: updateDate,
                rowUUID: rowID.raw
            )
            row.isPresent = isPresent
            row.drawingVersion = 3
            try await actor.insert(row)
            return row
        }
    }

    /// 실제 획이 하나 있는 `PKDrawing` 데이터.
    ///
    /// `PKStroke` 는 생성마다 다른 `randomSeed` 를 받아 `dataRepresentation()` 이 호출마다 달라진다.
    /// 보관본이 원본을 그대로 옮겼는지 **바이트로** 비교하려면 만들어 둔 값을 재사용해야 한다.
    private static let inkData: Data = makeInk(at: 5)
    private static let otherInkData: Data = makeInk(at: 9)

    private static func makeInk(at seed: CGFloat) -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: seed, y: seed), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }

    @Test("지우기 후 — 목록에는 보관본만 남지만 대표는 여전히 빈 활성 행이다")
    func eraseHidesEmptyRowFromListWhileKeepingItRepresentative() async throws {
        let harness = try Harness()
        let activeRowID = BibleDrawingRowID.issue()
        let archiveRowID = BibleDrawingRowID.issue()
        let carvedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let erasedAt = Date(timeIntervalSince1970: 1_700_000_900)   // 지우기가 더 나중이다

        try await harness.seed(rowID: activeRowID, lineData: Self.inkData, updateDate: carvedAt, isPresent: true)

        let outcome = try await harness.actor.archiveAndResetVerseDrawing(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: activeRowID, archiveRowID: archiveRowID),
            chapter: Self.chapter,
            now: erasedAt
        )
        #expect(outcome == .archived)

        // ① 저장소 조회는 그대로다 — 두 행 다 준다. 빈 활성 행이 `updateDate` 최신이라 **맨 위**에 온다.
        //    거르지 않으면 이 행이 "불러올 수 없는 필사 데이터입니다." 로 그려지던 자리다.
        let rows = try await harness.database.fetchDrawings(chapter: Self.chapter, verse: Self.verse)
        #expect(rows.count == 2)
        #expect(rows.first?.rowKey == activeRowID.raw)
        #expect(rows.first?.lineData == nil)

        // ② 목록에는 보관본만 보인다. 날짜도 원래 필사 시각이다.
        let listed = rows.historyRows()
        #expect(listed.count == 1)
        #expect(listed.first?.rowKey == archiveRowID.raw)
        #expect(listed.first?.updateDate == carvedAt)
        #expect(listed.first?.lineData == Self.inkData)

        // ③ 그래도 대표는 빈 활성 행이다 — 캔버스는 비어 보이고 지운 획이 되살아나지 않는다.
        #expect(rows.mainDrawing()?.rowKey == activeRowID.raw)
        #expect(rows.mainDrawing()?.lineData == nil)
        let snapshots = try await harness.actor.loadDrawingSnapshots(chapter: Self.chapter)
            .filter { $0.verse == Self.verse }
        #expect(snapshots.count == 2)
        #expect(snapshots.representative()?.rowID == activeRowID)
        #expect(snapshots.representative()?.lineData == nil)

        // ④ 함정 대조 (§8-7 ★) — **걸러낸 목록으로** 대표를 고르면 보관본이 승격돼 지운 획이 되살아난다.
        //    그래서 필터는 목록에만 두고 조회·대표 선택 경로에는 넣지 않는다.
        #expect(listed.mainDrawing()?.rowKey == archiveRowID.raw)
    }

    @Test("historyRows() 는 길이가 아니라 stroke 로 가른다 — 살아남은 행의 순서는 그대로다")
    func historyRowsFiltersByStrokeNotLength() async throws {
        let harness = try Harness()
        // 지우개로 전부 지운 행: 유효한 PKDrawing 이라 `lineData` 는 비어 있지 않은데 stroke 는 0개다.
        let fullyErased = PKDrawing().dataRepresentation()
        #expect(!fullyErased.isEmpty)

        let newerInk = BibleDrawingRowID(raw: "row-ink-newer")
        let olderInk = BibleDrawingRowID(raw: "row-ink-older")
        try await harness.seed(rowID: newerInk, lineData: Self.inkData,
                               updateDate: Date(timeIntervalSince1970: 500))
        try await harness.seed(rowID: BibleDrawingRowID(raw: "row-erased"), lineData: fullyErased,
                               updateDate: Date(timeIntervalSince1970: 400))
        try await harness.seed(rowID: BibleDrawingRowID(raw: "row-garbage"), lineData: Data([1, 2, 3]),
                               updateDate: Date(timeIntervalSince1970: 300))
        try await harness.seed(rowID: olderInk, lineData: Self.otherInkData,
                               updateDate: Date(timeIntervalSince1970: 200))
        try await harness.seed(rowID: BibleDrawingRowID(raw: "row-nil"), lineData: nil,
                               updateDate: Date(timeIntervalSince1970: 100))

        let rows = try await harness.database.fetchDrawings(chapter: Self.chapter, verse: Self.verse)
        #expect(rows.count == 5)

        let listed = rows.historyRows()
        #expect(listed.map(\.rowKey) == [newerInk.raw, olderInk.raw])
    }
}
