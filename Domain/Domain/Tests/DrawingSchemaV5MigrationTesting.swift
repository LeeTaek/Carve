//
//  DrawingSchemaV5MigrationTesting.swift
//  DomainTest
//
//  V5 — 즐겨찾기(`FavoriteVerse`) 엔티티 추가. V4 store 가 lightweight 로 올라오고 필사 행을 건드리지 않는지.
//
//  V4 에 엔티티를 끼워 넣지 않고 V5 로 올린 것이 이 파일의 전제다. 이미 V4 로 열린 store(2.0.0 개발 · 검증 빌드)는
//  같은 버전 번호의 **다른** 모델을 찾지 못해 `Cannot use staged migration with an unknown model version`(134504)으로
//  열리지 않았다(2026-09-15 SwiftData 단독 실험). 출시본(V3) store 는 두 방식 모두 열렸다.
//  ⚠️ 2026-09-17 정정 — 그 실험이 확인한 것은 134504 까지다. 앱에서 V1 폴백을 거쳐 `fatalError` 로 끝난다는 것은 관측이 아니었다.
//  실제로는 **V1 폴백이 성공한다** — 2026-09-15 실기기(dev 저장소)에서 V4 빌드가 「데이터 마이그레이션이 완료」 알림까지 갔고,
//  DOWN-L2(2026-09-16)와 MIG-F1(2026-09-17)에서는 저장소가 `DrawingVO` 스키마로 바뀌고 필사가 사라진 것을 확인했다.
//  2.0.0 부터는 모르는 스키마 저장소를 폴백하지 않고 막는다(`LocalStoreLoadFailureTesting`).
//
//  Copyright © 2026 leetaek. All rights reserved.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

@Suite("V5 — 즐겨찾기 엔티티 추가 마이그레이션")
struct DrawingSchemaV5MigrationTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)

    /// 2.0.0 개발 빌드가 지금까지 만든 모양의 V4 store(즐겨찾기 엔티티 없음)를 만들고 **닫는다.**
    ///
    /// 컨테이너를 이 함수 안에서만 살려 두는 것이 중요하다 — 같은 파일을 앱 스키마로 다시 열어야 하므로.
    private static func seedV4Store(at directory: URL) throws {
        let container = try ModelContainer(
            for: Schema([DrawingSchemaV4.BibleDrawing.self, DrawingSchemaV4.BiblePageDrawing.self]),
            configurations: ModelConfiguration(url: V4StoreHarness.storeURL(in: directory))
        )
        let context = ModelContext(container)
        let row = DrawingSchemaV4.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_750_000_000),
            layoutMetadataData: Data("layout".utf8),
            rowUUID: "row-v4"
        )
        row.isPresent = true
        row.drawingVersion = 3
        context.insert(row)
        try context.save()
    }

    /// 앱 스키마로 열어 즐겨찾기 하나를 저장하고 닫는다.
    private static func save(_ favorite: FavoriteVerseSnapshot, at directory: URL) async throws {
        let container = try V4StoreHarness.openV4(at: directory)
        let repository = SwiftDataFavoriteVerseRepository(actor: SwiftDatabaseActor(modelContainer: container))
        try await repository.save(favorite)
    }

    @Test("V5 는 5.0.0 이고 V4 의 두 모델 클래스를 그대로 싣고 즐겨찾기만 더한다 — 플랜의 마지막 스키마다")
    func versionModelsAndPlanPosition() {
        #expect(DrawingSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        let models = DrawingSchemaV5.models.map { ObjectIdentifier($0) }
        #expect(models == [
            ObjectIdentifier(DrawingSchemaV4.BibleDrawing.self),
            ObjectIdentifier(DrawingSchemaV4.BiblePageDrawing.self),
            ObjectIdentifier(DrawingSchemaV5.FavoriteVerse.self)
        ])
        #expect(DrawingDataMigrationPlan.schemas.last?.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(FavoriteVerse.self == DrawingSchemaV5.FavoriteVerse.self)
    }

    @Test("V4 store 를 앱 스키마로 다시 열면 필사 행은 그대로이고 즐겨찾기를 저장할 수 있다")
    func v4StoreMigratesWithoutTouchingDrawings() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        try Self.seedV4Store(at: directory)

        let container = try V4StoreHarness.openV4(at: directory)
        let actor = SwiftDatabaseActor(modelContainer: container)

        let rows: [BibleDrawing] = try await actor.fetch(FetchDescriptor<BibleDrawing>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.rowKey == "row-v4")
        #expect(row.lineData == RealLegacyLineData.data)
        #expect(row.layoutMetadataData == Data("layout".utf8))
        #expect(row.drawingVersion == 3)
        #expect(row.isPresent == true)

        let repository = SwiftDataFavoriteVerseRepository(actor: actor)
        let favorite = FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: Self.chapter, verse: 1),
            sentence: "여호와는 나의 목자시니 내가 부족함이 없으리로다",
            lineData: RealLegacyLineData.data,
            createdDate: Date(timeIntervalSince1970: 1_760_000_000)
        )
        try await repository.save(favorite)
        #expect(try await repository.favorites() == [favorite])
    }

    @Test("즐겨찾기는 store 를 닫았다 다시 열어도 추가 당시의 필기와 함께 남는다")
    func favoritesPersistAcrossReopen() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let favorite = FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: Self.chapter, verse: 2),
            sentence: "그가 나를 푸른 초장에 누이시며",
            lineData: RealLegacyLineData.data,
            createdDate: Date(timeIntervalSince1970: 1_760_000_000)
        )

        try await Self.save(favorite, at: directory)

        let reopened = SwiftDataFavoriteVerseRepository(
            actor: SwiftDatabaseActor(modelContainer: try V4StoreHarness.openV4(at: directory))
        )
        #expect(try await reopened.favorites() == [favorite])
        #expect(try await reopened.favoriteVerses(in: Self.chapter, translation: .NKRV) == [2])
    }
}
