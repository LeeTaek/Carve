//
//  DrawingSchemaV7MigrationTesting.swift
//  DomainTest
//
//  V7 — 필사책 메타데이터 엔티티(`DrawingNotebook`) 추가 (2.2 「회차별 필사책」 인터페이스 동결 ②).
//

@testable import Domain
import CoreData
import Foundation
import SwiftData
import Testing

@Suite("V7 — 필사책 메타데이터 엔티티 추가 마이그레이션")
struct DrawingSchemaV7MigrationTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)

    /// 2.0.x · 2.1 이 지금까지 만든 모양의 V6 저장소(필사 행 + 즐겨찾기 + 버전 · 기준점)를 만들고 **닫는다.**
    private static func seedV6Store(at directory: URL) throws {
        let container = try ModelContainer(
            for: Schema(DrawingSchemaV6.models),
            configurations: ModelConfiguration(url: V4StoreHarness.storeURL(in: directory))
        )
        let context = ModelContext(container)
        let row = DrawingSchemaV4.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_750_000_000),
            rowUUID: "row-v6"
        )
        row.isPresent = true
        context.insert(row)
        let english = DrawingSchemaV4.BibleDrawing(
            bibleTitle: BibleChapter(title: .psalms, chapter: 23, translation: .KJV),
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_750_000_050),
            rowUUID: "row-v6-kjv"
        )
        english.isPresent = true
        context.insert(english)
        context.insert(DrawingSchemaV6.FavoriteVerse(
            chapter: chapter,
            verse: 1,
            translation: .NKRV,
            sentence: "여호와는 나의 목자시니",
            lineData: RealLegacyLineData.data,
            createdDate: Date(timeIntervalSince1970: 1_750_000_100),
            favoriteID: "favorite-v6",
            knownEraseEpochs: ["E1"]
        ))
        context.insert(DrawingSchemaV6.DrawingEraseEpoch(
            epochID: "E1",
            knownEraseEpochs: [],
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_750_000_200)
        ))
        try context.save()
    }

    @Test("V7 는 7.0.0 이고 V6 의 다섯 모델 클래스를 그대로 싣고 필사책만 더한다 — 두 플랜의 마지막 스키마이자 앱 스키마다")
    func versionModelsAndPlanPosition() {
        #expect(DrawingSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        let models = DrawingSchemaV7.models.map { ObjectIdentifier($0) }
        #expect(models == [
            ObjectIdentifier(DrawingSchemaV4.BibleDrawing.self),
            ObjectIdentifier(DrawingSchemaV4.BiblePageDrawing.self),
            ObjectIdentifier(DrawingSchemaV6.FavoriteVerse.self),
            ObjectIdentifier(DrawingSchemaV6.VerseDrawingVersion.self),
            ObjectIdentifier(DrawingSchemaV6.DrawingEraseEpoch.self),
            ObjectIdentifier(DrawingSchemaV7.DrawingNotebook.self)
        ])
        #expect(DrawingDataMigrationPlan.schemas.last?.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(DrawingDataMigrationPlan.stages.count == 6)
        #expect(DrawingDataMigrationPlanFromV2.schemas.last?.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(DrawingDataMigrationPlanFromV2.stages.count == 5)
        #expect(AppStoreSchema.models.map { ObjectIdentifier($0) } == models)
        #expect(DrawingNotebook.self == DrawingSchemaV7.DrawingNotebook.self)
        // 필사 행 · 즐겨찾기 · 버전 · 기준점의 현재 별칭은 그대로다(V7 이 같은 클래스를 싣는다).
        #expect(BibleDrawing.self == DrawingSchemaV4.BibleDrawing.self)
        #expect(FavoriteVerse.self == DrawingSchemaV6.FavoriteVerse.self)
    }

    /// CloudKit private DB 미러링은 optional(또는 기본값) 속성만 받고, unique 제약 · 관계를 받지 않는다.
    @Test("CloudKit 제약 — 필사책 엔티티의 모든 속성은 optional 이고, unique · 관계가 없다")
    func cloudKitConstraints() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DrawingSchemaV7.models))
        let entity = try #require(model.entitiesByName["DrawingNotebook"], "DrawingNotebook 이 모델에 없다")
        #expect(Set(entity.attributesByName.keys) == [
            "notebookID", "name", "status", "createdAt", "updatedAt", "completedAt", "kind", "scopeData", "linkData"
        ])
        for attribute in entity.attributesByName.values {
            #expect(attribute.isOptional, "DrawingNotebook.\(attribute.name)")
        }
        // 상태는 열거형이 아니라 문자열 열이다(혼재 버전 규칙 ④).
        #expect(entity.attributesByName["status"]?.attributeType == .stringAttributeType)
        #expect(entity.uniquenessConstraints.isEmpty)
        #expect(entity.relationshipsByName.isEmpty)
    }

    @Test("V6 저장소를 앱 스키마로 열면 필사 행 · 즐겨찾기 · 기준점이 그대로이고 필사책은 비어 있다")
    func migratesV6StoreWithoutTouchingRows() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        try Self.seedV6Store(at: directory)
        let url = V4StoreHarness.storeURL(in: directory)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(6, 0, 0)))

        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<BibleDrawing>()).sorted { ($0.rowUUID ?? "") < ($1.rowUUID ?? "") }
        let favorites = try context.fetch(FetchDescriptor<FavoriteVerse>())
        let epochs = try context.fetch(FetchDescriptor<DrawingEraseEpoch>())

        // 행은 한 필드도 바뀌지 않는다 — 기본 필사책 행 형식 그대로(접두 없음).
        #expect(rows.map(\.rowUUID) == ["row-v6", "row-v6-kjv"])
        #expect(rows.map(\.titleName) == ["1-19Psalms.txt", "KJV-1-19Psalms.txt"])
        #expect(rows.map(\.translation) == [.NKRV, nil])
        #expect(rows.allSatisfy { $0.lineData == RealLegacyLineData.data && $0.isPresent == true })
        #expect(rows.compactMap { $0.titleName.flatMap(StoredBookKey.decodeRow)?.notebook } == [.default, .default])
        #expect(favorites.map(\.favoriteID) == ["favorite-v6"])
        #expect(EraseEpochSetCoding.decode(favorites.first?.knownEraseEpochs) == ["E1"])
        #expect(epochs.map(\.epochID) == ["E1"])
        // 기본 필사책의 메타데이터도 만들지 않는다 — 이름을 바꾸거나 완료를 표시할 때만 생긴다.
        #expect(try context.fetch(FetchDescriptor<DrawingNotebook>()).isEmpty)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(7, 0, 0)))
    }

    @Test("필사책 메타데이터와 필사책 행을 저장하고 다시 열어도 그대로다")
    func savesAndReloadsNotebooks() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let notebookID = NotebookID.make(uuid: UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!)
        let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        let completedAt = Date(timeIntervalSince1970: 1_760_086_400)
        do {
            let context = ModelContext(try V4StoreHarness.openV4(at: directory))
            let notebook = DrawingNotebook()
            notebook.notebookID = notebookID.rawValue
            notebook.name = "두 번째 필사"
            notebook.status = NotebookStatus.completed.rawValue
            notebook.createdAt = createdAt
            notebook.updatedAt = completedAt
            notebook.completedAt = completedAt
            notebook.kind = "personal"
            context.insert(notebook)
            let renamedDefault = DrawingNotebook()
            renamedDefault.notebookID = NotebookID.default.rawValue
            renamedDefault.name = "처음 필사"
            context.insert(renamedDefault)
            context.insert(BibleDrawing(
                page: NotebookChapter(notebook: notebookID, chapter: Self.chapter),
                verse: 1,
                lineData: RealLegacyLineData.data,
                rowUUID: "row-notebook"
            ))
            try context.save()
        }

        let context = ModelContext(try V4StoreHarness.openV4(at: directory))
        let notebooks = try context.fetch(FetchDescriptor<DrawingNotebook>()).sorted { ($0.notebookID ?? "") < ($1.notebookID ?? "") }
        let rows = try context.fetch(FetchDescriptor<BibleDrawing>())

        #expect(notebooks.map(\.notebookID) == [notebookID.rawValue, "default"])
        let saved = try #require(notebooks.first)
        #expect(saved.name == "두 번째 필사")
        #expect(NotebookStatus(stored: saved.status) == .completed)
        #expect(saved.createdAt == createdAt && saved.updatedAt == completedAt && saved.completedAt == completedAt)
        #expect(saved.kind == "personal" && saved.scopeData == nil && saved.linkData == nil)
        #expect(NotebookStatus(stored: notebooks.last?.status) == .active)
        #expect(rows.count == 1)
        #expect(rows.first?.titleName == "nb_\(notebookID.rawValue)~1-19Psalms.txt")
        #expect(rows.first?.translation == .NKRV)
        #expect(rows.first?.titleName.flatMap(StoredBookKey.decodeRow) == StoredRowKey(title: .psalms, translation: .NKRV, notebook: notebookID))
    }

    @Test("로더는 V7 저장소를 아는 모델로 가르고 그대로 연다")
    func loaderTreatsV7StoreAsKnown() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let url = V4StoreHarness.storeURL(in: directory)
        do {
            let context = ModelContext(try V4StoreHarness.openV4(at: directory))
            let notebook = DrawingNotebook()
            notebook.notebookID = NotebookID.default.rawValue
            context.insert(notebook)
            try context.save()
        }

        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(7, 0, 0)))
        #expect(LocalStoreLoader.plan(for: LocalStoreLoader.storeKind(at: url), isLegacySchemaMismatch: true) == .block(.openFailed))
        guard case .ready(let container) = LocalStoreLoader.load(at: url, cloudKitDatabase: .none) else {
            Issue.record("V7 저장소를 열지 못했다")
            return
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<DrawingNotebook>()) == 1)
    }
}
