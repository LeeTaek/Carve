//
//  LegacyStoreMigrationTesting.swift
//  CarveFeatureTest
//
//  V3 store → V5 스키마 → 조회 → 합성. 1.3.0 필사가 화면 좌표에 닿기까지의 전 구간 (§10-2 · §14 13)
//

import CoreGraphics
import Foundation
import PencilKit
import SwiftData
import Testing

@testable import CarveFeature
@testable import Domain

/// **층을 잇는 테스트.**
///
/// `DrawingSchemaV4MigrationTesting` 은 V3 store 가 마이그레이션에서 살아남는지를 보고,
/// `DrawingCodecTesting` · `DrawingCodecLegacyMigrationTesting` 은 손으로 만든 스냅샷이 어디 놓이는지를 본다.
/// 그 사이 — **마이그레이션이 실제로 뱉은 행을 `SwiftDataDrawingRepository` 가 읽어 codec 에 넘기는 구간** — 은
/// 어느 쪽에도 없었다. 이 파일이 그 구간을 잇는다.
///
/// - Important: 여기서도 확인되지 않는 것 — 실제 사용자 데이터(D8 의 225행)·CloudKit 수신·실기기 렌더링.
///              입력은 어디까지나 fixture 다. 통과는 "코드가 규약대로 돈다" 이지 "사용자 데이터가 무사하다" 가 아니다.
@Suite("V3 → V5 — store 부터 화면 좌표까지")
struct LegacyStoreMigrationTesting {
    private let codec = DrawingCodec()
    /// multiLine(높이 189)이 한 절 안에 들어가도록 넉넉한 줄 간격을 쓴다. verse 3 의 writingRect.origin = (0, 480).
    private let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 240)
    private let columnOrigin = CGPoint(x: 100, y: 0)
    private static let tolerance: CGFloat = 0.5

    // MARK: 하네스

    private static func makeStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "carve-v3-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func storeURL(in directory: URL) -> URL {
        directory.appending(path: "Carve.test.sqlite", directoryHint: .notDirectory)
    }

    /// 1.3.0 이 쓰던 **V3 스키마 그대로** store 를 만들고 실사용 blob 을 넣은 뒤 닫는다.
    /// V4 의 `rowUUID` · `layoutMetadataData` 는 이 스키마에 아예 없다.
    ///
    /// - Important: `isPresent` 를 **켜지 않는다.** 2026-09-16 시뮬레이터 실측 — 1.3.0 을 설치해 직접 필사한 뒤
    ///              store 를 열어 보니 `ZISPRESENT = 0` 이었다. 출시본의 저장 경로(`CombinedCanvasFeature`)가
    ///              그 필드를 건드리지 않고 V3 모델 기본값 `false` 가 그대로 남기 때문이다.
    ///              절당 행이 하나면 `DrawingRepresentativeRule` 의 결과는 같지만, 히스토리 행이 여럿일 때는
    ///              `isPresent` 분기가 아니라 `updateDate` → 행 키 분기를 탄다. 실제 데이터에 맞춘다.
    private static func seedV3Store(at directory: URL, verse: Int, lineData: Data) throws {
        let container = try ModelContainer(
            for: Schema([DrawingSchemaV3.BibleDrawing.self, DrawingSchemaV3.BiblePageDrawing.self]),
            configurations: ModelConfiguration(url: storeURL(in: directory))
        )
        let context = ModelContext(container)
        let row = DrawingSchemaV3.BibleDrawing(
            bibleTitle: OwnershipTestSupport.chapter, verse: verse, lineData: lineData
        )
        context.insert(row)
        try context.save()
    }

    /// 앱과 같은 방식으로 연다 — 현재 스키마(V5) + 전체 마이그레이션 플랜. CloudKit 만 뺀다.
    private static func openWithAppSchema(at directory: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(DrawingSchemaV5.models),
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL(in: directory))
        )
    }

    private func context(active: [Int: BibleDrawingRowID]) -> DrawingEditContext {
        DrawingEditContext(layout: layout, columnOrigin: columnOrigin, activeRowIDs: active)
    }

    // MARK: 전 구간

    @Test("V3 store 의 legacy 행이 V5 로 올라온 뒤 조회·합성까지 좌표 그대로 간다")
    func v3StoreReachesCanvasCoordinatesUnchanged() async throws {
        let directory = try Self.makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = LegacyDrawingFixture.multiLine
        let stored = try sample.drawing()
        try Self.seedV3Store(at: directory, verse: 3, lineData: stored.dataRepresentation())

        // 여기서 V3 → V4 → V5 가 실제로 돈다.
        let container = try Self.openWithAppSchema(at: directory)
        let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
        let snapshots = try await repository.load(chapter: OwnershipTestSupport.chapter)

        // 마이그레이션은 좌표 형식을 건드리지 않는다 (§10-2). rowUUID 도 소급 발급하지 않는다 (§8-7).
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.verse == 3)
        #expect(snapshot.drawingVersion == 1)
        #expect(snapshot.metadata == nil)
        // 실측대로 꺼진 채 올라온다 — 마이그레이션이 대표 표식을 새로 켜 주지 않는다.
        #expect(snapshot.isPresent == false)
        #expect(snapshot.rowID.raw.hasPrefix("\(BibleTitle.genesis.rawValue).1.3."))
        // 마이그레이션이 blob 을 재인코딩하지 않았는지 — 바이트가 그대로여야 한다.
        #expect(snapshot.lineData == stored.dataRepresentation())
        let reloaded = try PKDrawing(data: try #require(snapshot.lineData))
        #expect(reloaded.strokes.count == sample.expectedStrokeCount)

        // 그 스냅샷이 화면에서 가는 자리 — writingRect(verse 3).origin (0, 480) + columnOrigin (100, 0) + 실측 (21, 30).
        let composed = codec.compose(snapshots: snapshots, layout: layout, columnOrigin: columnOrigin)
        let displayed = try PKDrawing(data: composed.data)
        #expect(displayed.strokes.count == sample.expectedStrokeCount)
        #expect(abs(displayed.bounds.minX - 121) < Self.tolerance)
        #expect(abs(displayed.bounds.minY - 510) < Self.tolerance)
        #expect(composed.legacyVerses == [3])
        #expect(composed.undecodableVerses.isEmpty)
    }

    /// **R28 이 현실이 되는지 보는 자리.**
    ///
    /// legacy 행은 무변환으로 놓이지만, 그 절을 편집해 저장하면 `drawingVersion` 이 3 으로 승격되고
    /// 좌표가 **첫 밑줄 기준**으로 다시 적힌다 (§10-2 정책 5). 라벨과 내용이 함께 바뀌어야 하며,
    /// 한쪽만 바뀌면 다음에 열 때 필사가 밀린다.
    @Test("마이그레이션된 legacy 행을 편집하면 v3 로 승격되고 다시 열어도 기존 획이 제자리다")
    func editingMigratedLegacyRowPromotesItWithoutMovingExistingInk() async throws {
        let directory = try Self.makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = LegacyDrawingFixture.multiLine
        try Self.seedV3Store(at: directory, verse: 3, lineData: try sample.drawing().dataRepresentation())

        let container = try Self.openWithAppSchema(at: directory)
        let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
        let composed = codec.compose(
            snapshots: try await repository.load(chapter: OwnershipTestSupport.chapter),
            layout: layout, columnOrigin: columnOrigin
        )
        let before = try PKDrawing(data: composed.data)

        // 절 3 안에 획 하나를 더한다 — 실제 편집과 같은 경로로 저장 명령을 만든다.
        let added = OwnershipTestSupport.stroke(
            from: CGPoint(x: 150, y: 520), to: CGPoint(x: 200, y: 520), seed: 77, creationTime: 2_000
        )
        let edited = PKDrawing(strokes: before.strokes + [added])
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: edited.dataRepresentation(), context: context(active: composed.activeRowIDs)
        )
        #expect(result.mutations.count == 1)
        try await repository.apply(result.mutations, chapter: OwnershipTestSupport.chapter)

        // 저장 뒤 행은 v3 + metadata 를 갖는다. 라벨만 오르고 좌표가 그대로면 이 다음이 깨진다.
        let after = try await repository.load(chapter: OwnershipTestSupport.chapter)
        let saved = try #require(after.first)
        #expect(after.count == 1)
        #expect(saved.drawingVersion == 3)
        #expect(saved.metadata != nil)

        // 다시 합성하면 원래 legacy 획은 **획 하나하나가** 그 자리에 있어야 한다.
        // 전체 bounds 비교로는 부족하다 — 더한 획이 기존 bounds 안에 들어가고, 내부가 섞여도 겉 상자는 같다.
        let recomposed = codec.compose(snapshots: after, layout: layout, columnOrigin: columnOrigin)
        let displayed = try PKDrawing(data: recomposed.data)
        #expect(displayed.strokes.count == sample.expectedStrokeCount + 1)
        #expect(recomposed.legacyVerses.isEmpty)

        var unmatched = displayed.strokes.map(\.renderBounds)
        for box in before.strokes.map(\.renderBounds) {
            let index = try #require(unmatched.firstIndex {
                abs($0.minX - box.minX) < Self.tolerance && abs($0.minY - box.minY) < Self.tolerance
                    && abs($0.width - box.width) < Self.tolerance && abs($0.height - box.height) < Self.tolerance
            }, "편집·저장 왕복에서 기존 획이 움직였다: \(box)")
            unmatched.remove(at: index)
        }
        // 남은 하나가 방금 더한 획이다. renderBounds 는 획 굵기를 포함하므로 중심으로 본다.
        #expect(unmatched.count == 1)
        let addedBox = try #require(unmatched.first)
        #expect(abs(addedBox.midY - 520) < 5)
        #expect(abs(addedBox.midX - 175) < 5)
    }

    @Test("절마다 줄 수가 다른 레이아웃에서도 legacy 행은 자기 절의 writingRect 원점에 놓인다")
    func legacyRowLandsOnItsOwnVerseInNonUniformLayout() async throws {
        let directory = try Self.makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = LegacyDrawingFixture.multiLine
        try Self.seedV3Store(at: directory, verse: 3, lineData: try sample.drawing().dataRepresentation())

        // 균일 레이아웃 가정을 깬다 — 앞 절이 길어 verse 3 의 원점이 한참 아래로 밀린 장.
        let mixed = ChapterLayoutBuilder().build(
            chapter: OwnershipTestSupport.chapter,
            writingWidth: 320,
            setting: OwnershipTestSupport.setting(lineSpace: 240),
            isLeftHanded: false,
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 1),
                VerseLayoutInput(verse: 2, textLineCount: 4),
                VerseLayoutInput(verse: 3, textLineCount: 2),
                VerseLayoutInput(verse: 4, textLineCount: 3)
            ]
        )

        let container = try Self.openWithAppSchema(at: directory)
        let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
        let composed = codec.compose(
            snapshots: try await repository.load(chapter: OwnershipTestSupport.chapter),
            layout: mixed, columnOrigin: columnOrigin
        )
        let displayed = try PKDrawing(data: composed.data)

        // 앞 절 길이와 무관하게 자기 절의 원점 + 실측 bounds 다.
        let region = try #require(mixed.region(verse: 3))
        #expect(abs(displayed.bounds.minX - (region.writingRect.minX + columnOrigin.x + sample.expectedBounds.minX)) < Self.tolerance)
        #expect(abs(displayed.bounds.minY - (region.writingRect.minY + columnOrigin.y + sample.expectedBounds.minY)) < Self.tolerance)
        #expect(composed.legacyVerses == [3])
        for stroke in displayed.strokes {
            #expect(composed.ownership.owner(of: stroke) == 3)
        }
    }
}
