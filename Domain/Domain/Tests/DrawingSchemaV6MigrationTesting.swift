//
//  DrawingSchemaV6MigrationTesting.swift
//  DomainTest
//
//  V6 — 절 필기 버전 · 전체 삭제 기준점 엔티티 추가와 즐겨찾기의 K 필드 (정책 §12-6).
//

@testable import Domain
import CoreData
import Foundation
import SwiftData
import Testing

@Suite("V6 — 버전 · 기준점 엔티티 추가 마이그레이션")
struct DrawingSchemaV6MigrationTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)

    /// TestFlight 2.0.0 빌드가 지금까지 만든 모양의 V5 저장소(필사 행 + 즐겨찾기)를 만들고 **닫는다.**
    private static func seedV5Store(at directory: URL) throws {
        let container = try ModelContainer(
            for: Schema(DrawingSchemaV5.models),
            configurations: ModelConfiguration(url: V4StoreHarness.storeURL(in: directory))
        )
        let context = ModelContext(container)
        let row = DrawingSchemaV4.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_750_000_000),
            rowUUID: "row-v5"
        )
        row.isPresent = true
        context.insert(row)
        context.insert(DrawingSchemaV5.FavoriteVerse(
            chapter: chapter,
            verse: 1,
            translation: .NKRV,
            sentence: "여호와는 나의 목자시니",
            lineData: RealLegacyLineData.data,
            createdDate: Date(timeIntervalSince1970: 1_750_000_100),
            favoriteID: "favorite-v5"
        ))
        try context.save()
    }

    @Test("V6 는 6.0.0 이고 필사 행 두 클래스를 그대로 싣고 즐겨찾기 · 버전 · 기준점을 싣는다 — 플랜의 마지막 스키마다")
    func versionModelsAndPlanPosition() {
        #expect(DrawingSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        let models = DrawingSchemaV6.models.map { ObjectIdentifier($0) }
        #expect(models == [
            ObjectIdentifier(DrawingSchemaV4.BibleDrawing.self),
            ObjectIdentifier(DrawingSchemaV4.BiblePageDrawing.self),
            ObjectIdentifier(DrawingSchemaV6.FavoriteVerse.self),
            ObjectIdentifier(DrawingSchemaV6.VerseDrawingVersion.self),
            ObjectIdentifier(DrawingSchemaV6.DrawingEraseEpoch.self)
        ])
        #expect(DrawingDataMigrationPlan.schemas.last?.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(AppStoreSchema.models.map { ObjectIdentifier($0) } == models)
        #expect(FavoriteVerse.self == DrawingSchemaV6.FavoriteVerse.self)
    }

    /// CloudKit private DB 미러링은 optional(또는 기본값) 속성만 받고, unique 제약을 받지 않는다.
    /// 어기면 앱 실행 중 동기화 설정이 실패한다 — 시뮬레이터 시험에는 entitlement 가 없어 여기서 먼저 막는다.
    @Test("CloudKit 제약 — 새 엔티티의 모든 속성은 optional 이거나 기본값이 있고, unique · 관계가 없다")
    func cloudKitConstraints() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DrawingSchemaV6.models))
        for name in ["FavoriteVerse", "VerseDrawingVersion", "DrawingEraseEpoch"] {
            let entity = try #require(model.entitiesByName[name], "\(name) 이 모델에 없다")
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(name).\(attribute.name)")
            }
            #expect(entity.uniquenessConstraints.isEmpty, "\(name)")
            #expect(entity.relationshipsByName.isEmpty, "\(name)")
        }
    }

    @Test("V5 저장소를 앱 스키마로 열면 필사 행 · 즐겨찾기가 그대로이고, 즐겨찾기의 K 는 빈 집합이다")
    func migratesV5StoreWithoutTouchingRows() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        try Self.seedV5Store(at: directory)
        let url = V4StoreHarness.storeURL(in: directory)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(5, 0, 0)))

        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<BibleDrawing>())
        let favorites = try context.fetch(FetchDescriptor<FavoriteVerse>())

        #expect(rows.map(\.rowUUID) == ["row-v5"])
        #expect(rows.first?.lineData == RealLegacyLineData.data)
        #expect(favorites.map(\.favoriteID) == ["favorite-v5"])
        #expect(favorites.first?.knownEraseEpochs == nil)
        #expect(EraseEpochSetCoding.decode(favorites.first?.knownEraseEpochs) == [])
        #expect(try context.fetch(FetchDescriptor<VerseDrawingVersion>()).isEmpty)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(6, 0, 0)))
    }

    @Test("버전 · 기준점을 저장하고 다시 열어도 그대로다 — 큰 획이 외부 저장으로 빠져도 같다")
    func savesAndReloadsVersionsAndEpochs() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let ink = Data((0..<1_048_576).map { UInt8($0 % 251) })
        let fingerprint = VerseContentFingerprint.make(lineData: ink, drawingVersion: 3, layoutMetadataBlob: nil)
        do {
            let context = ModelContext(try V4StoreHarness.openV4(at: directory))
            let version = VerseDrawingVersion()
            version.versionID = "version-1"
            version.kind = VerseDrawingVersionKind.edit.rawValue
            version.titleName = Self.chapter.title.rawValue
            version.titleChapter = Self.chapter.chapter
            version.verse = 1
            version.parentIDs = EraseEpochSetCoding.encode(["legacy-abc"])
            version.lineData = ink
            version.drawingVersion = 3
            version.contentFingerprint = fingerprint
            version.knownEraseEpochs = EraseEpochSetCoding.encode(["E1"])
            context.insert(version)
            context.insert(DrawingEraseEpoch(epochID: "E2", knownEraseEpochs: ["E1"], deviceID: "device-1", createdAt: Date()))
            try context.save()
        }

        let context = ModelContext(try V4StoreHarness.openV4(at: directory))
        let versions = try context.fetch(FetchDescriptor<VerseDrawingVersion>())
        let epochs = try context.fetch(FetchDescriptor<DrawingEraseEpoch>())

        #expect(versions.count == 1)
        #expect(versions.first?.lineData == ink)
        #expect(versions.first?.contentFingerprint == fingerprint)
        #expect(EraseEpochSetCoding.decode(versions.first?.knownEraseEpochs) == ["E1"])
        #expect(versions.first.flatMap { VerseDrawingVersionKind(rawValue: $0.kind ?? "") } == .edit)
        #expect(epochs.map(\.epochID) == ["E2"])
        #expect(EraseEpochSetCoding.decode(epochs.first?.knownEraseEpochs) == ["E1"])
    }

    /// 같은 집합이면 같은 문자열이어야 레코드끼리 비교할 수 있다. 읽지 못한 값을 빈 집합으로 읽으면
    /// "아무 삭제도 몰랐다" 가 돼 판정이 바뀐다.
    @Test("K 집합 형식 — 정렬한 JSON 배열이고, 비면 nil, 읽지 못하면 빈 집합이 아니라 nil 이다")
    func epochSetCoding() {
        #expect(EraseEpochSetCoding.encode(["E2", "E1"]) == "[\"E1\",\"E2\"]")
        #expect(EraseEpochSetCoding.encode([]) == nil)
        #expect(EraseEpochSetCoding.decode(nil) == [])
        #expect(EraseEpochSetCoding.decode("") == [])
        #expect(EraseEpochSetCoding.decode("[\"E2\",\"E1\"]") == ["E1", "E2"])
        #expect(EraseEpochSetCoding.decode("깨진 값") == nil)
    }

    @Test("legacy 수용 · 삭제 관측은 의도적 버전이 아니다")
    func intentionalKinds() {
        let intentional = VerseDrawingVersionKind.allCases.filter(\.isIntentional)
        #expect(Set(intentional) == [.edit, .select, .clear])
    }
}
