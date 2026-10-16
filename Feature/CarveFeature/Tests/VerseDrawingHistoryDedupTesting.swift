//
//  VerseDrawingHistoryDedupTesting.swift
//  CarveFeatureTest
//
//  2.1 필사 불러오기 — 이전 필사 기록은 같은 내용의 행을 하나로 보인다 (정책 §7-3 「수신 후 동일 버전을 하나로 취급」)
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 같은 내용으로 쓰는 잉크. `PKDrawing` 바이트는 만들 때마다 달라지므로 한 번 만들어 재사용한다 — 다시 만들면 다른 내용이다.
private let sameInk = dedupInk(y: 10)
/// 다른 내용의 잉크.
private let otherInk = dedupInk(y: 40)
/// 단일 Canvas 가 쓴 v3 행의 레이아웃 메타데이터.
private let dedupMetadata = DrawingLayoutMetadata(
    baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "history-dedup"
)

/// 획 하나짜리 필기 — 목록은 획 없는 행을 거른다(`DrawingContentRule.hasStrokes`).
private func dedupInk(y offset: Double) -> Data {
    let points = (0..<8).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index) * 10, y: offset), timeOffset: Double(index) * 0.02,
            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
}

/// 두 기기가 오프라인으로 같은 백업을 불러오면 같은 내용의 행이 `rowUUID` 만 다르게 둘 생긴다(`docs/backup-import-design.md` §7).
///
/// 이 파일이 고정하는 것:
/// - 같은 내용(`VerseContentFingerprint`)의 행은 목록에 하나만 보인다 — `updateDate` 가 가장 늦은 것, 같으면 행 키 사전순(작은 쪽)
/// - 잉크 · 좌표 형식 · 레이아웃 메타데이터 중 하나라도 다르면 다 보이고, 대표 행은 같은 내용의 더 늦은 보관 행이 있어도 남는다
/// - 남긴 행을 고르면 그 행이 저장소의 대표가 되고, 숨긴 행은 지워지지 않는다
///
/// 목록만 보는 시험은 효과 없는 `setDrawings` 로 넣는다 — `State` 가 Equatable 이 아니라 실제 Store 로 본다.
/// 저장소를 거치는 시험은 자기 인메모리 컨테이너를 연다 — 공유 actor 를 깨우지 않는다.
@Suite("이전 필사 기록 — 같은 내용 행을 하나로 보인다 (정책 §7-3)")
@MainActor
struct VerseDrawingHistoryDedupTesting {
    private static let chapter = BibleChapter(title: .habakkuk, chapter: 3)
    private static let verse = 4

    /// 저장소에 미리 넣을 v3 행 하나.
    private struct SeedRow {
        let key: String
        let ink: Data
        let isPresent: Bool
        let updatedAt: TimeInterval
    }

    // MARK: 헬퍼

    /// 한 절의 행 하나. 기본은 단일 Canvas 가 쓴 v3 + 메타데이터 보관 행이다.
    private static func row(
        _ key: String, ink: Data?, at seconds: TimeInterval, isPresent: Bool = false,
        drawingVersion: Int? = 3, metadata: DrawingLayoutMetadata? = dedupMetadata
    ) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: key), isPresent: isPresent,
            updateDate: Date(timeIntervalSince1970: seconds), lineData: ink,
            drawingVersion: drawingVersion, metadata: metadata
        )
    }

    /// 목록 상태에 들어오는 길목(`setDrawings`)으로 넣고, 목록에 보이는 행의 키를 순서대로 돌려준다.
    private static func listed(_ rows: [VerseDrawingSnapshot]) -> [String] {
        let store = Store(initialState: VerseDrawingHistoryFeature.State(page: chapter.inDefaultNotebook, verse: verse)) {
            VerseDrawingHistoryFeature()
        }
        store.send(.setDrawings(rows))
        return store.drawings.map(\.rowID.raw)
    }

    /// 앱 스키마의 인메모리 저장소에 v3 행을 넣는다. @Model 은 컨테이너를 연 뒤에 만든다(iOS 17).
    private static func makeStore(seeding rows: [SeedRow]) throws -> (ModelContainer, SwiftDatabaseActor) {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        // 같은 내용 행은 메타데이터 바이트도 같다 — 한 번 인코딩해 함께 쓴다.
        let metadataBlob = try dedupMetadata.encodedBlob()
        for seed in rows {
            let row = BibleDrawing(
                bibleTitle: chapter, verse: verse, lineData: seed.ink,
                updateDate: Date(timeIntervalSince1970: seed.updatedAt),
                layoutMetadataData: metadataBlob, rowUUID: seed.key
            )
            row.drawingVersion = 3
            row.isPresent = seed.isPresent
            context.insert(row)
        }
        try context.save()
        return (container, SwiftDatabaseActor(modelContainer: container))
    }

    /// 그 저장소를 보는 이전 필사 기록 스토어. 쓰기 게이트는 소유가 확인된 환경이다.
    private static func makeHistoryStore(storeActor: SwiftDatabaseActor) -> StoreOf<VerseDrawingHistoryFeature> {
        let database = withDependencies { $0.createSwiftDataActor = storeActor } operation: { DrawingDatabase() }
        return Store(initialState: VerseDrawingHistoryFeature.State(page: chapter.inDefaultNotebook, verse: verse)) {
            VerseDrawingHistoryFeature()
        } withDependencies: {
            $0.drawingData = database
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(.ownedForTesting)
        }
    }

    /// 저장소에서 `isPresent` 인 행의 키.
    private static func presentKeys(in storeActor: SwiftDatabaseActor) async throws -> [String] {
        try await storeActor.verseDrawingSnapshots(chapter: chapter, verse: verse).filter(\.isPresent).map(\.rowID.raw)
    }

    /// 조건이 참이 될 때까지 기다린다 — 조회 · 저장 효과는 스토어 밖에서 돈다.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while true {
            if try await condition() { return }
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: 묶기

    @Test("같은 내용의 보관 행 둘은 하나로 보인다 — updateDate 가 늦은 쪽을 남기고, 다른 내용의 대표 행은 그대로다")
    func sameContentArchivedRowsAreListedOnce() {
        // given: 지금 대표(다른 내용) + 두 기기가 같은 백업을 넣어 생긴 같은 내용 보관 행 둘. 조회 순서(updateDate 최신순) 그대로다.
        let rows = [
            Self.row("row-current", ink: otherInk, at: 300, isPresent: true),
            Self.row("row-copy-later", ink: sameInk, at: 200),
            Self.row("row-copy-earlier", ink: sameInk, at: 100)
        ]

        // when / then: 같은 내용은 늦은 행 하나만 남고, 순서는 조회 그대로다.
        #expect(Self.listed(rows) == ["row-current", "row-copy-later"])
    }

    @Test("updateDate 가 같으면 행 키 사전순으로 작은 쪽을 남긴다 — 들어온 순서와 무관하다")
    func tieKeepsSmallerRowKey() {
        let first = Self.row("row-b", ink: sameInk, at: 100)
        let second = Self.row("row-a", ink: sameInk, at: 100)

        #expect(Self.listed([first, second]) == ["row-a"])
        #expect(Self.listed([second, first]) == ["row-a"])
    }

    @Test("잉크 · 좌표 형식 · 레이아웃 메타데이터 중 하나만 달라도 다른 내용이라 다 보인다")
    func differentContentIsNotMerged() {
        let wider = DrawingLayoutMetadata(
            baseWritingWidth: 480, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "history-dedup"
        )
        // 맨 아래 기준 행과 한 가지씩만 다르다.
        let rows = [
            Self.row("row-ink", ink: otherInk, at: 400),
            Self.row("row-version", ink: sameInk, at: 300, drawingVersion: 2),
            Self.row("row-metadata", ink: sameInk, at: 200, metadata: wider),
            Self.row("row-base", ink: sameInk, at: 100)
        ]

        #expect(Self.listed(rows) == ["row-ink", "row-version", "row-metadata", "row-base"])
    }

    // MARK: 대표

    @Test("대표(isPresent) 행은 같은 내용의 더 늦은 보관 행이 있어도 남는다 — 지금 보이는 회차 표시가 사라지지 않는다")
    func presentRowStaysOverLaterSameContentRow() throws {
        let rows = [
            Self.row("row-later-copy", ink: sameInk, at: 300),
            Self.row("row-present", ink: sameInk, at: 100, isPresent: true)
        ]
        let representative = try #require(rows.representative())

        #expect(representative.rowID.raw == "row-present")
        #expect(Self.listed(rows) == ["row-present"])
    }

    @Test("isPresent 행이 없는 절(1.3.0 legacy 등)은 가장 늦은 행이 대표이고, 같은 내용을 묶어도 그 행이 남는다")
    func latestRowStaysWhenNoRowIsPresent() throws {
        // given: legacy 행(좌표 형식 nil · 메타데이터 없음) — isPresent 가 모두 false 다.
        let rows = [
            Self.row("row-latest", ink: sameInk, at: 300, drawingVersion: nil, metadata: nil),
            Self.row("row-other", ink: otherInk, at: 200, drawingVersion: nil, metadata: nil),
            Self.row("row-older-copy", ink: sameInk, at: 100, drawingVersion: nil, metadata: nil)
        ]
        let representative = try #require(rows.representative())

        #expect(representative.rowID.raw == "row-latest")
        #expect(Self.listed(rows) == ["row-latest", "row-other"])
    }

    @Test("두 기기가 같은 백업을 넣은 모양 — 현재 행 둘 · 보관 행 둘이 각각 하나로 보이고, 남은 현재 행이 캔버스의 대표다")
    func doubleImportShowsOneRowPerContent() throws {
        // given: 같은 백업 항목을 넣어 updateDate 까지 같고 rowUUID 만 다르다. 둘 다 현재 행이다.
        let rows = [
            Self.row("row-b-current", ink: sameInk, at: 300, isPresent: true),
            Self.row("row-a-current", ink: sameInk, at: 300, isPresent: true),
            Self.row("row-b-archived", ink: otherInk, at: 100),
            Self.row("row-a-archived", ink: otherInk, at: 100)
        ]
        let representative = try #require(rows.representative())

        let listed = Self.listed(rows)

        #expect(listed == ["row-a-current", "row-a-archived"])
        #expect(representative.rowID.raw == "row-a-current")
    }

    @Test("지운 절을 두 기기가 같이 불러온 모양 — 비운 현재 행은 숨기고, 같은 내용의 보관 행은 하나로 보인다")
    func clearedVerseShowsArchivedContentOnce() {
        let rows = [
            Self.row("row-b-cleared", ink: nil, at: 900, isPresent: true, metadata: nil),
            Self.row("row-a-cleared", ink: nil, at: 900, isPresent: true, metadata: nil),
            Self.row("row-b-archived", ink: sameInk, at: 100),
            Self.row("row-a-archived", ink: sameInk, at: 100)
        ]

        #expect(Self.listed(rows) == ["row-a-archived"])
    }

    // MARK: 고르기

    @Test("남긴 행을 고르면 그 행이 저장소의 대표가 된다 — 숨긴 같은 내용 행은 지우지 않고 대표에서만 내린다")
    func pickingKeptRowMakesItRepresentative() async throws {
        // given: 지금 대표(다른 내용) + 같은 내용 보관 행 둘이 든 저장소.
        let (container, storeActor) = try Self.makeStore(seeding: [
            SeedRow(key: "row-current", ink: otherInk, isPresent: true, updatedAt: 300),
            SeedRow(key: "row-copy-later", ink: sameInk, isPresent: false, updatedAt: 200),
            SeedRow(key: "row-copy-earlier", ink: sameInk, isPresent: false, updatedAt: 100)
        ])
        defer { withExtendedLifetime(container) {} }
        let history = Self.makeHistoryStore(storeActor: storeActor)

        // when: 목록을 읽으면 같은 내용은 늦은 행 하나만 보인다.
        history.send(.view(.fetchDrawings))
        try await waitUntil { history.hasLoaded }
        #expect(history.drawings.map(\.rowID.raw) == ["row-current", "row-copy-later"])

        // 그 남긴 행을 고른다.
        let kept = try #require(history.drawings.first { $0.rowID.raw == "row-copy-later" })
        history.send(.view(.selectDrawing(kept)))
        try await waitUntil { try await Self.presentKeys(in: storeActor) == ["row-copy-later"] }

        // then: 저장소의 대표가 남긴 행이다. 세 행은 그대로 있다 — 숨긴 행도 지우지 않았다.
        let stored = try await storeActor.verseDrawingSnapshots(chapter: Self.chapter, verse: Self.verse)
        #expect(stored.representative()?.rowID.raw == "row-copy-later")
        #expect(Set(stored.map(\.rowID.raw)) == ["row-current", "row-copy-later", "row-copy-earlier"])
        #expect(history.drawings.filter(\.isPresent).map(\.rowID.raw) == ["row-copy-later"])

        // 다시 열어도 같은 내용은 하나로 보이고, 고른 행이 지금 보이는 회차다.
        let reopened = Self.makeHistoryStore(storeActor: storeActor)
        reopened.send(.view(.fetchDrawings))
        try await waitUntil { reopened.hasLoaded }
        #expect(reopened.drawings.map(\.rowID.raw) == ["row-current", "row-copy-later"])
        #expect(reopened.drawings.filter(\.isPresent).map(\.rowID.raw) == ["row-copy-later"])
    }
}
