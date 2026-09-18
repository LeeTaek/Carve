//
//  LocalStoreLoadFailureTesting.swift
//  DomainTest
//
//  MIG-F1 — 로컬 저장소를 앱 스키마로 열지 못했을 때 (정책 §3 표 4행 · 테스트 계획 "추가 확인 항목").
//
//  이전 `ModelContainer.liveValue` 는 열기 실패를 전부 "버전 없는 1.0.x 저장소" 로 보고 V1 스키마로 **같은 파일을** 다시 열었다.
//  더 새 스키마의 저장소에서도 그 폴백이 성공해 필사가 사라진 채 앱이 열렸다(§5-1 DOWN-L2 · F7). 이 파일은 그 결함의 재현,
//  고친 판별(파일 불변 + 차단), 그리고 남겨야 하는 1.0.x 이관 경로를 함께 고정한다. 시작 화면의 진입 판정은 `LaunchRouteTesting` 이 본다.
//
//  CloudKit 없이 로컬 파일로만 본다 — 시뮬레이터 테스트에는 entitlement 가 없다(`V4StoreHarness` 와 같은 제약).
//

@testable import Domain
import Foundation
import SwiftData
import Testing

// MARK: - fixture

/// 테스트 전용 V6 — V5 의 `BibleDrawing` 에 optional 필드 하나를 더한 **앱이 모르는 더 새 스키마**다.
/// 2.0.0 뒤의 빌드가 만든 저장소를 2.0.0 이 여는 경우(TestFlight 에서 예전 빌드를 다시 까는 경우)를 흉내 낸다.
enum NewerStoreSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [BibleDrawing.self, DrawingSchemaV4.BiblePageDrawing.self, DrawingSchemaV5.FavoriteVerse.self]
    }

    /// V4 `BibleDrawing` 의 필드 그대로에 `addedInV6` 하나를 더했다.
    @Model
    final class BibleDrawing {
        var id: String!
        var titleName: String?
        var titleChapter: Int?
        var verse: Int?
        var creationDate: Date?
        var updateDate: Date?
        var translation: Translation? = Translation.NKRV
        var drawingVersion: Int? = 1
        var isPresent: Bool? = false
        @Attribute(.externalStorage) var lineData: Data?
        @Attribute(.externalStorage) var layoutMetadataData: Data?
        var rowUUID: String?
        var addedInV6: String?

        init() { }
    }
}

/// 반례 — 엔티티가 `DrawingVO` 하나뿐이지만 **어느 1.0.x 릴리스에도 없던 모양**(1.0.4~1.0.7 에 필드 하나를 더했다).
///
/// 엔티티 이름만 보고 V1 폴백을 허용하던 판별은 이런 저장소도 V1 스키마로 갈아치웠다(2026-09-17 리뷰).
enum UnrecognizedDrawingVOStore {
    @Model
    final class DrawingVO {
        var id: String!
        var titleName: String?
        var titleChapter: Int?
        var section: Int?
        var creationDate: Date?
        var updateDate: Date?
        @Attribute(.externalStorage) var lineData: Data?
        var isWritten: Bool = false
        /// 확인된 1.0.x 모양에는 없는 필드.
        var memo: String?

        init() { }
    }
}

/// 확인된 1.0.x 저장소 모양. 앱이 허용 목록으로 쓰는 `UnversionedDrawingStore` 의 정의를 그대로 심는다.
enum UnversionedShape: CaseIterable, Sendable, CustomTestStringConvertible {
    /// 1.0.0 ~ 1.0.3 — 날짜 필드가 없다.
    case release100
    /// 1.0.4 ~ 1.0.7 — `creationDate` · `updateDate` 가 있다.
    case release104

    var testDescription: String {
        switch self {
        case .release100: "1.0.0~1.0.3"
        case .release104: "1.0.4~1.0.7"
        }
    }

    /// 이 모양의 행이 V1 → V2 를 거친 뒤 가지는 행 키. `creationDate` 가 없으면 원래 `id` 를 그대로 쓴다.
    var migratedRowID: String {
        switch self {
        case .release100: "1-01Genesis.txt.1.1"
        case .release104: "1-01Genesis.txt.1.1.1700000000"
        }
    }
}

/// 저장소 파일을 만들고 읽는 헬퍼. 만든 컨테이너는 함수 안에서만 살린다 — 같은 파일을 다른 스키마로 다시 열어야 한다.
private enum StoreFixture {
    static let chapter = BibleChapter(title: .genesis, chapter: 1)

    /// V6 저장소에서 읽은 필사 행. 컨테이너가 닫힌 뒤에도 비교할 수 있게 값으로 옮긴다.
    struct V6Row: Equatable {
        let rowUUID: String?
        let lineData: Data?
        let addedInV6: String?
    }

    static func seedV6Store(at url: URL) throws {
        let container = try ModelContainer(for: Schema(NewerStoreSchemaV6.models), configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let row = NewerStoreSchemaV6.BibleDrawing()
        row.id = "\(chapter.title.rawValue).\(chapter.chapter).1.1750000000"
        row.titleName = chapter.title.rawValue
        row.titleChapter = chapter.chapter
        row.verse = 1
        row.isPresent = true
        row.drawingVersion = 3
        row.lineData = RealLegacyLineData.data
        row.rowUUID = "row-v6"
        row.addedInV6 = "v6"
        context.insert(row)
        try context.save()
    }

    /// V6 스키마로 다시 열어 필사 행을 읽는다.
    static func v6Rows(at url: URL) throws -> [V6Row] {
        let container = try ModelContainer(for: Schema(NewerStoreSchemaV6.models), configurations: ModelConfiguration(url: url))
        return try ModelContext(container)
            .fetch(FetchDescriptor<NewerStoreSchemaV6.BibleDrawing>())
            .map { V6Row(rowUUID: $0.rowUUID, lineData: $0.lineData, addedInV6: $0.addedInV6) }
    }

    /// 확인된 1.0.x 모양으로 저장소를 만들고 닫는다.
    static func seedUnversionedStore(_ shape: UnversionedShape, at url: URL) throws {
        switch shape {
        case .release100:
            let container = try ModelContainer(
                for: Schema([UnversionedDrawingStore.Release100.DrawingVO.self]),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            let row = UnversionedDrawingStore.Release100.DrawingVO()
            row.id = "\(chapter.title.rawValue).\(chapter.chapter).1"
            row.titleName = chapter.title.rawValue
            row.titleChapter = chapter.chapter
            row.section = 1
            row.lineData = RealLegacyLineData.data
            row.isWritten = true
            context.insert(row)
            try context.save()

        case .release104:
            let container = try ModelContainer(
                for: Schema([UnversionedDrawingStore.Release104.DrawingVO.self]),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            let row = UnversionedDrawingStore.Release104.DrawingVO()
            row.id = "\(chapter.title.rawValue).\(chapter.chapter).1"
            row.titleName = chapter.title.rawValue
            row.titleChapter = chapter.chapter
            row.section = 1
            row.creationDate = Date(timeIntervalSince1970: 1_700_000_000)
            row.updateDate = Date(timeIntervalSince1970: 1_700_000_100)
            row.lineData = RealLegacyLineData.data
            row.isWritten = true
            context.insert(row)
            try context.save()
        }
    }

    /// 반례 저장소 — 엔티티 이름은 같고 필드가 다르다.
    static func seedUnrecognizedDrawingVOStore(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema([UnrecognizedDrawingVOStore.DrawingVO.self]),
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let row = UnrecognizedDrawingVOStore.DrawingVO()
        row.id = "\(chapter.title.rawValue).\(chapter.chapter).1"
        row.titleName = chapter.title.rawValue
        row.section = 1
        row.lineData = RealLegacyLineData.data
        row.memo = "확인되지 않은 모양"
        context.insert(row)
        try context.save()
    }

    /// 반례 저장소를 자기 스키마로 다시 열어 행 수와 잉크를 읽는다.
    static func unrecognizedRows(at url: URL) throws -> [Data?] {
        let container = try ModelContainer(
            for: Schema([UnrecognizedDrawingVOStore.DrawingVO.self]),
            configurations: ModelConfiguration(url: url)
        )
        return try ModelContext(container).fetch(FetchDescriptor<UnrecognizedDrawingVOStore.DrawingVO>()).map(\.lineData)
    }

    static func seedV1Store(at url: URL) throws {
        let container = try ModelContainer(for: Schema(DrawingSchemaV1.models), configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        context.insert(DrawingVO(bibleTitle: chapter, verse: 1, lineData: RealLegacyLineData.data))
        try context.save()
    }

    /// 저장소 본체와 WAL 의 바이트.
    ///
    /// `-shm` 은 비교하지 않는다 — SQLite 의 공유 메모리 색인이라 메타데이터를 **읽기만 해도** 바뀐다(2026-09-17 실측).
    static func storeBytes(at url: URL) throws -> [Data] {
        let wal = URL(fileURLWithPath: url.path + "-wal")
        return [try Data(contentsOf: url), (try? Data(contentsOf: wal)) ?? Data()]
    }

    /// 이전 `liveValue` 의 폴백 그대로 — 버전을 가리지 않고 V1 스키마로 같은 파일을 연다.
    static func openV1Only(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema([DrawingVO.self]),
            migrationPlan: MigrationPlanV1Only.self,
            configurations: ModelConfiguration(url: url)
        )
    }
}

// MARK: - 저장소

@Suite("MIG-F1 — 로컬 저장소를 열지 못하면 파일을 건드리지 않고 들어가지 않는다")
struct LocalStoreLoadFailureTesting {

    private func withStore(_ body: (URL) async throws -> Void) async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        try await body(V4StoreHarness.storeURL(in: directory))
    }

    // MARK: 수정 전 — 결함 재현

    /// 이전 구현이 하던 일을 그대로 흉내 낸다. 이 테스트가 깨지면(폴백이 실패하게 되면) 전제가 바뀐 것이니
    /// 테스트 계획 §5-1 F7 · MIG-F1 기록을 다시 본다.
    @Test("무조건 V1 폴백은 더 새 스키마 저장소에서도 성공해 필사를 지운다 — 이 파일이 막는 결함")
    func unconditionalV1FallbackWipesNewerStore() async throws {
        try await withStore { url in
            try StoreFixture.seedV6Store(at: url)

            // 앱 스키마로는 열리지 않는다 — CoreData 134504(unknown model version)가 `loadIssueModelContainer` 로 올라온다.
            #expect(throws: SwiftDataError.loadIssueModelContainer) {
                try ModelContainer(
                    for: Schema([BibleDrawing.self, BiblePageDrawing.self, FavoriteVerse.self]),
                    migrationPlan: DrawingDataMigrationPlan.self,
                    configurations: ModelConfiguration(url: url)
                )
            }
            // 이전 폴백은 실패하지 않는다.
            _ = try StoreFixture.openV1Only(at: url)

            // ★ 같은 파일이 V1 스키마로 바뀌었고 필사 행이 없다.
            #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(1, 0, 0)))
            #expect(try StoreFixture.v6Rows(at: url).isEmpty)
        }
    }

    /// 들어가면 안 되는 이유 — V1 전용 컨테이너는 `BibleDrawing` 을 모른다. 크래시하지도 오류를 내지도 않아 "저장됨" 처럼 보인다.
    /// iOS 26.2 시뮬레이터 실측이다. SwiftData 가 달라져 저장이 던지게 되면 이 기대를 고치고 MIG-F1 기록도 고친다.
    @Test("V1 전용 컨테이너에서는 필사 조회가 비고, 저장은 오류 없이 끝나지만 다시 읽히지 않는다")
    func v1OnlyContainerDropsDrawingSavesSilently() async throws {
        try await withStore { url in
            let container = try StoreFixture.openV1Only(at: url)
            let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
            let chapter = StoreFixture.chapter
            let metadata = DrawingLayoutMetadata(
                baseWritingWidth: 372, baseWritingHeight: 60, baseUnderlineAnchors: [0, 30], layoutSignature: "mig-f1"
            )

            let generation = try await repository.load(chapter: chapter).generation
            await #expect(throws: Never.self) {
                try await repository.apply(
                    [.create(verse: 1, rowID: .issue(), data: RealLegacyLineData.data, metadata: metadata)],
                    chapter: chapter,
                    generation: generation
                )
            }
            #expect(try await repository.load(chapter: chapter).snapshots.isEmpty)
        }
    }

    // MARK: 수정 후

    @Test("더 새 스키마 저장소는 열지 않고 가려 막는다 — 파일 바이트와 필사가 그대로다")
    func newerStoreIsBlockedAndLeftUntouched() async throws {
        try await withStore { url in
            try StoreFixture.seedV6Store(at: url)
            let before = try StoreFixture.storeBytes(at: url)

            let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none)

            guard case .unavailable(let failure) = outcome else {
                Issue.record("막지 않았다: \(outcome)")
                return
            }
            #expect(failure == .unknownVersion)
            #expect(try StoreFixture.storeBytes(at: url) == before)
            #expect(try StoreFixture.v6Rows(at: url) == [
                StoreFixture.V6Row(rowUUID: "row-v6", lineData: RealLegacyLineData.data, addedInV6: "v6")
            ])
        }
    }

    @Test("확인된 1.0.x 저장소는 이전처럼 V1 로 옮기고, 재실행하면 앱 스키마로 이어진다", arguments: UnversionedShape.allCases)
    func unversionedStoreKeepsLegacyMigrationPath(_ shape: UnversionedShape) async throws {
        try await withStore { url in
            try StoreFixture.seedUnversionedStore(shape, at: url)

            do {
                let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none)
                guard case .legacyMigration(let container) = outcome else {
                    Issue.record("V1 폴백을 타지 않았다: \(outcome)")
                    return
                }
                let rows = try ModelContext(container).fetch(FetchDescriptor<DrawingVO>())
                #expect(rows.count == 1)
                #expect(rows.first?.lineData == RealLegacyLineData.data)
            }

            // 재실행 — 이제 저장소가 V1 과 맞으므로 앱 스키마가 V1 → V5 로 옮긴다.
            #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(1, 0, 0)))
            guard case .ready(let container) = LocalStoreLoader.load(at: url, cloudKitDatabase: .none) else {
                Issue.record("재실행에서 앱 스키마로 열리지 않았다")
                return
            }
            let drawings = try ModelContext(container).fetch(FetchDescriptor<BibleDrawing>())
            #expect(drawings.count == 1)
            #expect(drawings.first?.id == shape.migratedRowID)
            #expect(drawings.first?.lineData == RealLegacyLineData.data)
        }
    }

    /// 리뷰(2026-09-17) 지적 — 엔티티 이름이 `DrawingVO` 하나뿐이라는 것은 1.0.x 의 **필요조건일 뿐**이다.
    /// 이름만 보고 폴백하던 판별은 이런 저장소도 V1 스키마로 갈아치웠다.
    @Test("엔티티 이름만 같고 확인되지 않은 모양이면 V1 폴백 없이 막는다")
    func unrecognizedDrawingVOStoreIsBlocked() async throws {
        try await withStore { url in
            try StoreFixture.seedUnrecognizedDrawingVOStore(at: url)
            let before = try StoreFixture.storeBytes(at: url)

            #expect(LocalStoreLoader.storeKind(at: url) == .unknown)
            guard case .unavailable(let failure) = LocalStoreLoader.load(at: url, cloudKitDatabase: .none) else {
                Issue.record("막지 않았다 — 확인되지 않은 모양을 V1 폴백에 태웠다")
                return
            }
            #expect(failure == .unknownVersion)
            #expect(try StoreFixture.storeBytes(at: url) == before)
            #expect(try StoreFixture.unrecognizedRows(at: url) == [RealLegacyLineData.data])
        }
    }

    @Test("손상된 파일은 V1 폴백으로 덮어쓰지 않고 막는다")
    func unreadableStoreIsBlockedAndLeftUntouched() async throws {
        try await withStore { url in
            let garbage = Data(repeating: 0x5A, count: 8192)
            try garbage.write(to: url)

            guard case .unavailable(let failure) = LocalStoreLoader.load(at: url, cloudKitDatabase: .none) else {
                Issue.record("막지 않았다")
                return
            }
            #expect(failure == .unreadable)
            #expect(try Data(contentsOf: url) == garbage)
        }
    }

    // MARK: 판별

    @Test("저장소를 열지 않고 가른다 — 아는 버전 · 확인된 1.0.x · 모르는 모델")
    func storeKindSeparatesVersions() async throws {
        try await withStore { url in
            _ = try ModelContainer(
                for: Schema([BibleDrawing.self, BiblePageDrawing.self, FavoriteVerse.self]),
                migrationPlan: DrawingDataMigrationPlan.self,
                configurations: ModelConfiguration(url: url)
            )
            #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(5, 0, 0)))
        }
        try await withStore { url in
            try StoreFixture.seedV1Store(at: url)
            #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(1, 0, 0)))
        }
        for shape in UnversionedShape.allCases {
            try await withStore { url in
                try StoreFixture.seedUnversionedStore(shape, at: url)
                #expect(LocalStoreLoader.storeKind(at: url) == .unversionedLegacy, "\(shape.testDescription)")
            }
        }
        try await withStore { url in
            try StoreFixture.seedV6Store(at: url)
            #expect(LocalStoreLoader.storeKind(at: url) == .unknown)
        }
        try await withStore { url in
            try StoreFixture.seedUnrecognizedDrawingVOStore(at: url)
            #expect(LocalStoreLoader.storeKind(at: url) == .unknown)
        }
    }

    @Test("메타데이터를 읽지 못하면 읽지 못한 것이고, 파일이 없으면 없는 것이다")
    func unreadableAndMissingStores() async throws {
        try await withStore { url in
            #expect(LocalStoreLoader.storeKind(at: url) == .missing)
            try Data(repeating: 0x5A, count: 8192).write(to: url)
            #expect(LocalStoreLoader.storeKind(at: url) == .unreadable)
        }
    }

    @Test("열지 못한 저장소의 처리 — V1 폴백은 확인된 1.0.x 저장소이면서 loadIssue 일 때만이다")
    func planTable() {
        #expect(LocalStoreLoader.plan(for: .unversionedLegacy, isLoadIssue: true) == .fallbackToV1)
        #expect(LocalStoreLoader.plan(for: .unversionedLegacy, isLoadIssue: false) == .block(.openFailed))
        // ★ 이전 구현이 V1 폴백으로 필사를 지우던 경우다.
        #expect(LocalStoreLoader.plan(for: .unknown, isLoadIssue: true) == .block(.unknownVersion))
        // 아는 버전인데 열지 못했다 — V1 과 맞는 저장소도 폴백하지 않는다. 폴백해도 할 일이 없고 재실행 안내만 되풀이된다.
        #expect(LocalStoreLoader.plan(for: .known(Schema.Version(1, 0, 0)), isLoadIssue: true) == .block(.openFailed))
        #expect(LocalStoreLoader.plan(for: .known(Schema.Version(5, 0, 0)), isLoadIssue: true) == .block(.openFailed))
        #expect(LocalStoreLoader.plan(for: .missing, isLoadIssue: true) == .block(.openFailed))
        #expect(LocalStoreLoader.plan(for: .unreadable, isLoadIssue: true) == .block(.unreadable))
    }

    @Test("막았을 때 앱이 쥐는 컨테이너는 메모리에만 있고 CloudKit 에 붙지 않는다")
    func standInContainerStaysInMemory() throws {
        let container = try LocalStoreLoader.makeUnavailableStandIn()
        #expect(!container.configurations.isEmpty)
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly && $0.cloudKitContainerIdentifier == nil })
        // 앱 스키마를 알아서 잘못 불려도 크래시하지 않고 비어 있다.
        #expect(try ModelContext(container).fetch(FetchDescriptor<BibleDrawing>()).isEmpty)
    }
}
