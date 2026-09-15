//
//  BibleTitleDrawingRecordTesting.swift
//  DomainTest
//
//  탐색 장 목록 — 성경 한 권에서 필사 기록이 있는 장과 가장 최근에 필사한 장을 고르는 조회.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import Dependencies

@Suite("성경 한 권의 필사 기록 요약")
struct BibleTitleDrawingRecordTesting {
    @Test("획이 있는 행만 기록으로 치고, 그중 가장 최근에 필사한 장을 고른다")
    func recordCountsOnlyRowsWithStrokes() async throws {
        let (actor, database) = try Self.makeDatabase()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = [
            Self.row(.songOfSongs, chapter: 2, lineData: Self.strokeData, at: base),
            Self.row(.songOfSongs, chapter: 5, lineData: Self.strokeData, at: base + 100),
            // 보관 행은 원래 필사 시각을 지닌 기록이다.
            Self.row(.songOfSongs, chapter: 4, lineData: Self.strokeData, at: base + 50, isPresent: false),
            // 지우기로 비운 행과 지우개로 전부 지운 행은 더 최근이어도 기록이 아니다.
            Self.row(.songOfSongs, chapter: 7, lineData: nil, at: base + 200),
            Self.row(.songOfSongs, chapter: 3, lineData: PKDrawing().dataRepresentation(), at: base + 300),
            // 다른 성경의 기록은 섞이지 않는다.
            Self.row(.isaiah, chapter: 1, lineData: Self.strokeData, at: base + 400)
        ]
        for row in rows {
            try await actor.insert(row)
        }

        let record = try await database.fetchDrawingRecord(title: .songOfSongs)

        #expect(record == BibleTitleDrawingRecord(drawnChapters: [2, 4, 5], latestChapter: 5))
    }

    @Test("필사 기록이 없으면 빈 요약을 돌려준다")
    func recordIsEmptyWithoutDrawings() async throws {
        let (_, database) = try Self.makeDatabase()

        let record = try await database.fetchDrawingRecord(title: .ruth)

        #expect(record == BibleTitleDrawingRecord())
    }

    /// 테스트마다 인메모리 컨테이너를 따로 만들어 다른 테스트의 행과 섞이지 않게 한다.
    private static func makeDatabase() throws -> (SwiftDatabaseActor, DrawingDatabase) {
        let container = try ModelContainer(
            for: Schema([BibleDrawing.self, BiblePageDrawing.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let actor = SwiftDatabaseActor(modelContainer: container)
        let database = withDependencies {
            $0.createSwiftDataActor = actor
        } operation: {
            DrawingDatabase()
        }
        return (actor, database)
    }

    private static func row(
        _ title: BibleTitle,
        chapter: Int,
        lineData: Data?,
        at updateDate: Date,
        isPresent: Bool = true
    ) -> BibleDrawing {
        let row = BibleDrawing(
            bibleTitle: BibleChapter(title: title, chapter: chapter),
            verse: 1,
            lineData: lineData,
            updateDate: updateDate
        )
        row.isPresent = isPresent
        return row
    }

    private static var strokeData: Data {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)].enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: TimeInterval(index), size: CGSize(width: 5, height: 5),
                opacity: 1, force: 1, azimuth: 0, altitude: 0
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }
}
