//
//  NCanvasRowsAfterRemovalTesting.swift
//  CarveFeatureTest
//
//  2.1 N-Canvas 제거 — 2.0.x(N-Canvas) · 1.3.0 기기가 남긴 행을 단일 Canvas 가 읽고 이어 쓰는가 (사용자 출시 기준 ③의 자동 부분)
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 2.1 은 N-Canvas 를 지웠지만 2.0.x · 1.3.0 기기는 같은 계정에서 v1 · v2 행을 계속 만든다(결정 5 — 코덱의 v1 · v2 해석은 남긴다).
///
/// 이 파일이 고정하는 것:
/// - N-Canvas 가 남긴 세 모양 — v1(R18, 절 로컬 좌상단) · v2 · v3 를 편집해 v2 로 내리고 metadata 를 지운 행 — 이 **`writingRect` 원점**에 놓인다
/// - 그 절을 단일 Canvas 에서 고치면 **같은 행**이 v3 + metadata 로 올라가고, 다시 열어도 기존 획이 제자리다
/// - 이전 필사 기록에서 v2 보관 행을 고르면 그 행이 대표가 되고, 단일 Canvas 가 그 행을 제자리에 놓고 이어 쓴다
///
/// 실제 저장소(`SwiftDataDrawingRepository` · 인메모리 컨테이너)를 쓰는 시험은 시험마다 자기 컨테이너를 연다 — 공유 actor 를 깨우지 않는다.
@Suite("N-Canvas 제거 뒤 — 2.0.x 가 남긴 행을 단일 Canvas 가 읽고 이어 쓴다")
@MainActor
struct NCanvasRowsAfterRemovalTesting {
    private let codec = DrawingCodec()
    /// 4절 · 줄 30pt · 폭 320.
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
    private let columnOrigin = CGPoint(x: 100, y: 0)
    private static let chapter = OwnershipTestSupport.chapter
    private static let tolerance: CGFloat = 0.5
    /// N-Canvas 가 절 캔버스 로컬(`writingRect` 좌상단 원점)로 쓴 획의 시작점.
    private static let localStart = CGPoint(x: 24, y: 12)

    /// 2.0.x N-Canvas 가 남긴 행의 모양.
    enum NCanvasRow: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// R18 — N-Canvas 가 절 로컬 좌상단 좌표로 쓴 v1 행(1.3.0 · 2.0.x).
        case version1
        /// N-Canvas 가 쓴 v2 행(절 로컬 + 좌상단).
        case version2
        /// 단일 Canvas 가 쓴 v3 행을 N-Canvas 가 편집해 v2 로 내리고 metadata 를 지운 행.
        case downgradedFromVersion3

        var drawingVersion: Int { self == .version1 ? 1 : 2 }
        var testDescription: String { rawValue }
    }

    /// 저장소에 미리 넣을 행 하나.
    private struct SeedRow {
        let verse: Int
        let key: String
        let drawingVersion: Int
        let isPresent: Bool
        let updatedAt: TimeInterval
        let metadata: DrawingLayoutMetadata?
    }

    // MARK: 헬퍼

    /// 절 로컬 좌표의 획 한 개. PKDrawing 바이트는 매번 달라지므로 시험마다 한 번 만들어 재사용한다.
    private static func localInk(seed: UInt32) -> Data {
        let stroke = OwnershipTestSupport.stroke(
            from: localStart, to: CGPoint(x: localStart.x + 60, y: localStart.y), seed: seed, creationTime: 1_000
        )
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    private static func snapshot(verse: Int, key: String, kind: NCanvasRow, ink: Data) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: key), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 100), lineData: ink, drawingVersion: kind.drawingVersion, metadata: nil
        )
    }

    /// 획의 첫 점(캔버스 좌표).
    private static func anchor(_ stroke: PKStroke) -> CGPoint? {
        stroke.path.first.map { $0.location.applying(stroke.transform) }
    }

    /// N-Canvas 행이 단일 Canvas 에서 놓여야 하는 자리 — 절의 `writingRect` 원점 + `columnOrigin` + 절 로컬 좌표(무변환).
    private func expectedAnchor(verse: Int) throws -> CGPoint {
        let region = try #require(layout.region(verse: verse))
        return CGPoint(
            x: region.writingRect.minX + columnOrigin.x + Self.localStart.x,
            y: region.writingRect.minY + columnOrigin.y + Self.localStart.y
        )
    }

    private static func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < tolerance && abs(lhs.y - rhs.y) < tolerance
    }

    /// 앱 스키마의 인메모리 저장소에 행을 넣는다. @Model 은 컨테이너를 연 뒤에 만든다(iOS 17).
    private static func makeStore(seeding rows: [SeedRow], ink: Data) throws -> (ModelContainer, SwiftDatabaseActor) {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for seed in rows {
            let row = BibleDrawing(
                bibleTitle: chapter, verse: seed.verse, lineData: ink,
                updateDate: Date(timeIntervalSince1970: seed.updatedAt),
                layoutMetadataData: try seed.metadata?.encodedBlob(), rowUUID: seed.key
            )
            row.drawingVersion = seed.drawingVersion
            row.isPresent = seed.isPresent
            context.insert(row)
        }
        try context.save()
        return (container, SwiftDatabaseActor(modelContainer: container))
    }

    // MARK: 놓이는 자리

    @Test("N-Canvas 가 남긴 v1 · v2 · v3→v2 행은 무변환으로 절의 writingRect 원점에 놓인다 — 활성 행으로 남고 v1 만 legacy 로 센다")
    func nCanvasRowsLandAtWritingRectOrigin() throws {
        // 절마다 다른 획이다 — 같은 획(seed · 시각)이면 소유권 표의 획 식별 키가 겹친다.
        let snapshots = [
            Self.snapshot(verse: 1, key: "v1-1", kind: .version1, ink: Self.localInk(seed: 11)),
            Self.snapshot(verse: 2, key: "v2-2", kind: .version2, ink: Self.localInk(seed: 12)),
            Self.snapshot(verse: 3, key: "down-3", kind: .downgradedFromVersion3, ink: Self.localInk(seed: 13))
        ]

        let composed = codec.compose(snapshots: snapshots, layout: layout, columnOrigin: columnOrigin)
        let displayed = try PKDrawing(data: composed.data)

        #expect(composed.activeRowIDs == [
            1: BibleDrawingRowID(raw: "v1-1"), 2: BibleDrawingRowID(raw: "v2-2"), 3: BibleDrawingRowID(raw: "down-3")
        ])
        #expect(composed.legacyVerses == [1])
        #expect(composed.layoutMismatchVerses.isEmpty)
        #expect(composed.undecodableVerses.isEmpty)
        #expect(displayed.strokes.count == 3)
        for verse in 1...3 {
            let strokes = displayed.strokes.filter { composed.ownership.owner(of: $0) == verse }
            #expect(strokes.count == 1)
            let anchor = try #require(strokes.first.flatMap(Self.anchor))
            let expected = try expectedAnchor(verse: verse)
            #expect(Self.isClose(anchor, expected), "verse \(verse): \(anchor) ≠ \(expected)")
        }
    }

    // MARK: 이어 쓰기

    @Test("N-Canvas 행을 단일 Canvas 에서 고치면 같은 행이 v3 + metadata 로 저장되고, 다시 열어도 기존 획이 제자리다",
          arguments: NCanvasRow.allCases)
    func editingNCanvasRowPromotesSameRowToVersion3(kind: NCanvasRow) async throws {
        let ink = Self.localInk(seed: 21)
        let (container, actor) = try Self.makeStore(seeding: [
            SeedRow(verse: 2, key: "ncanvas-2", drawingVersion: kind.drawingVersion, isPresent: true, updatedAt: 100, metadata: nil)
        ], ink: ink)
        defer { withExtendedLifetime(container) {} }
        let repository = SwiftDataDrawingRepository(actor: actor)

        // given: 장을 열어 합성한다 — N-Canvas 행은 writingRect 원점에 있다.
        let loaded = try await repository.load(chapter: Self.chapter)
        let composed = codec.compose(snapshots: loaded.snapshots, layout: layout, columnOrigin: columnOrigin)
        let before = try PKDrawing(data: composed.data)
        let original = try #require(before.strokes.first.flatMap(Self.anchor))
        let expected = try expectedAnchor(verse: 2)
        #expect(Self.isClose(original, expected))

        // when: 2절 안에 획 하나를 더한다 — 실제 편집과 같은 경로로 저장 명령을 만들고 저장한다.
        let region = try #require(layout.region(verse: 2))
        let added = OwnershipTestSupport.stroke(
            from: CGPoint(x: columnOrigin.x + 150, y: region.writingRect.midY),
            to: CGPoint(x: columnOrigin.x + 200, y: region.writingRect.midY),
            seed: 22, creationTime: 2_000
        )
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: PKDrawing(strokes: before.strokes + [added]).dataRepresentation(),
            context: DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: composed.activeRowIDs)
        )
        // 새 행이 아니라 N-Canvas 가 남긴 그 행을 고친다.
        #expect(result.mutations.count == 1)
        guard case .replace(let verse, let rowID, _, _) = try #require(result.mutations.first) else {
            Issue.record("replace 가 아니다: \(result.mutations)"); return
        }
        #expect(verse == 2)
        #expect(rowID.raw == "ncanvas-2")
        try await repository.apply(result.mutations, chapter: Self.chapter, generation: loaded.generation)

        // then: 같은 행이 v3 + metadata 로 올라갔다.
        let after = try await repository.load(chapter: Self.chapter).snapshots
        #expect(after.count == 1)
        let saved = try #require(after.first)
        #expect(saved.rowID.raw == "ncanvas-2")
        #expect(saved.drawingVersion == 3)
        #expect(saved.metadata != nil)

        // 다시 열면 기존 획은 제자리이고, 더한 획도 함께 있다. 이제 legacy 가 아니다.
        let recomposed = codec.compose(snapshots: after, layout: layout, columnOrigin: columnOrigin)
        let displayed = try PKDrawing(data: recomposed.data)
        #expect(recomposed.legacyVerses.isEmpty)
        #expect(recomposed.layoutMismatchVerses.isEmpty)
        #expect(displayed.strokes.count == 2)
        let anchors = displayed.strokes.compactMap(Self.anchor)
        #expect(anchors.contains { Self.isClose($0, original) }, "기존 획이 움직였다: \(anchors) — 원래 \(original)")
    }

    // MARK: 이전 필사 기록

    @Test("이전 필사 기록에서 v2 보관 행을 고르면 그 행이 대표가 되고, 단일 Canvas 가 그 행을 제자리에 놓고 이어 쓴다")
    func pickingArchivedVersion2RowMakesItRepresentative() async throws {
        let ink = Self.localInk(seed: 31)
        let (container, actor) = try Self.makeStore(seeding: [
            // 지금 대표 — 단일 Canvas 가 쓴 v3 행.
            SeedRow(verse: 2, key: "current-v3", drawingVersion: 3, isPresent: true, updatedAt: 200, metadata: CanvasTestSupport.metadata()),
            // 2.0.x N-Canvas 가 남긴 보관 행 — v2, metadata 없음.
            SeedRow(verse: 2, key: "archived-v2", drawingVersion: 2, isPresent: false, updatedAt: 100, metadata: nil)
        ], ink: ink)
        defer { withExtendedLifetime(container) {} }
        let repository = SwiftDataDrawingRepository(actor: actor)
        #expect(try await repository.load(chapter: Self.chapter).snapshots.representativesByVerse()[2]?.rowID.raw == "current-v3")

        // when: 이력 화면에서 v2 보관 행을 고른다 — 같은 저장소를 보는 `drawingData` 로.
        let database = withDependencies { $0.createSwiftDataActor = actor } operation: { DrawingDatabase() }
        let history = Store(initialState: VerseDrawingHistoryFeature.State(title: Self.chapter, verse: 2)) {
            VerseDrawingHistoryFeature()
        } withDependencies: {
            $0.drawingData = database
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(.ownedForTesting)
        }
        history.send(.view(.fetchDrawings))
        let listDeadline = ContinuousClock.now + .seconds(2)
        while !history.hasLoaded, ContinuousClock.now < listDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let archived = try #require(history.drawings.first { $0.rowID.raw == "archived-v2" })
        history.send(.view(.selectDrawing(archived)))

        var representative: VerseDrawingSnapshot?
        let pickDeadline = ContinuousClock.now + .seconds(2)
        repeat {
            representative = try await repository.load(chapter: Self.chapter).snapshots.representativesByVerse()[2]
            if representative?.rowID.raw == "archived-v2" { break }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < pickDeadline

        // then: 고른 v2 행이 대표다 — 좌표 형식은 그대로(승격 · metadata 없음)다.
        let picked = try #require(representative)
        #expect(picked.rowID.raw == "archived-v2")
        #expect(picked.drawingVersion == 2)
        #expect(picked.metadata == nil)

        // 단일 Canvas 는 그 행을 활성 행으로 writingRect 원점에 놓는다.
        let loaded = try await repository.load(chapter: Self.chapter)
        let composed = codec.compose(snapshots: loaded.snapshots, layout: layout, columnOrigin: columnOrigin)
        #expect(composed.activeRowIDs[2]?.raw == "archived-v2")
        #expect(composed.legacyVerses.isEmpty)
        #expect(composed.layoutMismatchVerses.isEmpty)
        let shown = try PKDrawing(data: composed.data)
        #expect(shown.strokes.count == 1)
        let anchor = try #require(shown.strokes.first.flatMap(Self.anchor))
        let expected = try expectedAnchor(verse: 2)
        #expect(Self.isClose(anchor, expected))

        // 그 절을 고치면 고른 행이 v3 로 올라간다 — 다른 행을 덮지 않는다.
        let region = try #require(layout.region(verse: 2))
        let added = OwnershipTestSupport.stroke(
            from: CGPoint(x: columnOrigin.x + 150, y: region.writingRect.midY),
            to: CGPoint(x: columnOrigin.x + 200, y: region.writingRect.midY),
            seed: 32, creationTime: 3_000
        )
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: PKDrawing(strokes: shown.strokes + [added]).dataRepresentation(),
            context: DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: composed.activeRowIDs)
        )
        #expect(result.mutations.map(\.rowID.raw) == ["archived-v2"])
        try await repository.apply(result.mutations, chapter: Self.chapter, generation: loaded.generation)

        let after = try await repository.load(chapter: Self.chapter).snapshots
        #expect(after.count == 2)
        let promoted = try #require(after.first { $0.rowID.raw == "archived-v2" })
        #expect(promoted.drawingVersion == 3)
        #expect(promoted.metadata != nil)
        let untouched = try #require(after.first { $0.rowID.raw == "current-v3" })
        #expect(untouched.isPresent == false)
        #expect(after.representativesByVerse()[2]?.rowID.raw == "archived-v2")
    }
}
