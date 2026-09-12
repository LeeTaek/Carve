//
//  DrawingSchemaV4MigrationTesting.swift
//  DomainTest
//
//  Phase 1 — V4 additive schema. 설계 §10 검증.
//
//  이 파일이 확보하는 것은 두 가지다.
//  1. **V3 → V4 lightweight 마이그레이션이 데이터를 건드리지 않는가** (§10-1 · §10-2)
//  2. **V4 저장소에서 기존 경로(flag off = 현재 N Canvas)가 그대로 동작하는가** (§10-3)
//
//  2번이 Phase 1 의 존재 이유다. V4 는 forward-only 라 되돌릴 수단이 feature flag 뿐이고,
//  그때도 저장소는 V4 인 채로 남기 때문이다.
//
//  Copyright © 2026 leetaek. All rights reserved.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import Dependencies

// MARK: - 공용 하네스

/// 파일 기반 store 를 열고 닫는 헬퍼.
///
/// 인메모리 store 로는 마이그레이션을 태울 수 없다 — 같은 store 를 **다른 스키마로 다시 여는 것**이
/// 마이그레이션의 전제이기 때문이다. CloudKit 컨테이너로도 검증할 수 없다(시뮬레이터에
/// entitlement 가 없다, 설계 §18-5). 따라서 `cloudKitDatabase` 없이 로컬 파일로만 검증하고,
/// **CloudKit 제약 검증은 D7 로 이월한다.**
enum V4StoreHarness {

    /// 테스트마다 격리된 디렉터리를 만든다. sqlite 본체 외에 `-wal` / `-shm` /
    /// `.<name>_SUPPORT`(외부저장 blob) 이 함께 생기므로 디렉터리째 지우는 편이 안전하다.
    static func makeStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarveV4Migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeStoreDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `.externalStorage` 로 승격된 blob 이 실제로 파일로 떨어졌는지.
    ///
    /// 승격 임계값은 CoreData 내부값이라 테스트가 강제할 수 없으므로 **단정에 쓰지 않고**,
    /// 승격이 일어난 경우에만 마이그레이션 이후에도 파일이 남아 있는지 확인하는 데 쓴다.
    static func externalDataFiles(in directory: URL) -> [URL] {
        // CoreData 는 `.<storename>_SUPPORT/_EXTERNAL_DATA/<uuid>/<blob>` 로 떨군다.
        // 중간 디렉터리 이름을 가정하지 않고 트리를 훑는다.
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return walker.compactMap { $0 as? URL }
            .filter { $0.path.contains("_EXTERNAL_DATA") }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
    }

    static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Carve.sqlite")
    }

    /// **앱과 동일한 방식**으로 V4 컨테이너를 연다.
    ///
    /// `ModelContainer.liveValue` 는 `Schema([BibleDrawing.self, BiblePageDrawing.self])` 로
    /// 스키마를 구성하므로(별칭 경유), 같은 표현을 써야 "앱이 여는 스키마" 를 검증한 것이 된다.
    /// 차이는 `cloudKitDatabase` 를 주지 않는 것뿐이다.
    static func openV4(at directory: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema([BibleDrawing.self, BiblePageDrawing.self]),
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL(in: directory))
        )
    }
}

/// 마이그레이션 전에 기록해 둘 값. 마이그레이션 뒤 이 값과 대조한다.
struct SeededV3Row: Sendable, Equatable {
    let rowKey: String
    let titleName: String
    let titleChapter: Int
    let verse: Int
    let isPresent: Bool
    let drawingVersion: Int?
    let creationDate: Date
    let updateDate: Date
    let lineData: Data
}

// MARK: - fixture

/// 실기기 백업(§20-3 D8)에서 추출한 실사용 `lineData` 1건.
///
/// 원본은 `Feature/CarveFeature/Tests/LegacyDrawingFixture.swift` 의 `single` 샘플이다.
/// **Domain 테스트 타깃은 CarveFeature 테스트 타깃에 의존하지 않으므로** 그 타입을 가져올 수 없고,
/// 타깃 의존성을 추가하는 것은 프로젝트 설정 변경이라 금지돼 있다(AGENTS.md).
/// 그래서 같은 blob 의 base64 만 여기에 다시 둔다 — 합성 `PKDrawing` 이 아니라 실데이터를 쓰기 위함이다.
/// 어느 본문인지는 원본과 마찬가지로 기록하지 않는다(개인 필사 기록).
enum RealLegacyLineData {
    static let base64 =
        "AXdyZPABAAgAEhAAAAAAAAAAAAAAAAAAAAAAEhDlCftjVFpJA5w0WpmMRF8cGgYIABAAGAAaBggBEAEYASI3ChQNAAAAABUAAAAAHQAAAAAlAACAPxIUY29tLmFwcGxlLmluay5wZW5jaWwYA0EAAAAAAADwvyqw"
        + "AwoQi9fZqVFqQja9AmPB5WCU1BIGCAAQARgBGgYIABABGAAgACrsAgoQUWDxvV7mRDOtis4B0PZ8kxHzO1W1nGPHQRgTIKMCKNwNMhKamZk/6AMCABShtY4AAIA/AAA6sALeyP1B42+jQQAAAACuAHQPfgL0QUEM"
        + "lUEAEoM7zQB+EStQ9UGH94dBgEOLPPAA2RNRzQJCn6iGQeClGz3wANwTjVEJQhxQh0HAzEw98ADcE58dEkJw2o1BYJFtPfAA3BMuVBdCrLOVQXBokT36AIAUZE4YQrq+pEHg+6k9EAEAFgpxEkJKjq5B0MzMPSAB"
        + "BxfDSwpCbra3QRAv3T0uAfUX5tgAQuzxvEGwne89MgFDGKcZ8EEt6L5BAAAAPjMBTBi+8dlBwkC+QSgxCD4yAUMYDHnRQTJxtEEIgRU+EAH6FaCEz0HpjJ1BKLIdPvIAABToStlB1mSUQaAaLz6TAKwNoe7oQXDa"
        + "jUHASzc+VgCXCYQt+0FGlYpBEINAPhsAqwVAtgZC856IQTi0SD4MAKkESAAyFA0AAMBBFQAAcEEdAACAQSUAADBBQMCyxa3WBDoGCAAQABgAQhCMWUNQQuxFDYfdSthO794W"

    static var data: Data { Data(base64Encoded: base64)! }

    /// 추출 시점 실측값. 디코드 결과가 다르면 blob 이 손상된 것이다.
    static let expectedStrokeCount = 1

    /// `.externalStorage` 로 실제 승격되는 큰 blob.
    ///
    /// D8 실측에서 외부저장 행이 1건 있었으므로(§20-3) 그 경로도 함께 태운다.
    /// 실사용 blob 자체는 최대 111KB 라 전부 인라인이었다.
    ///
    /// - Note: 승격 임계값은 CoreData 내부값이라 문서화돼 있지 않다. 실측으로 934KB 는
    ///         **인라인으로 남았고** 약 1MB 를 넘겨야 외부 파일로 떨어졌다. 그래서 여유 있게
    ///         1.8MB 언저리를 만든다.
    static func makeLargeDrawingData(strokeCount: Int = 320, pointsPerStroke: Int = 220) -> Data {
        var strokes: [PKStroke] = []
        strokes.reserveCapacity(strokeCount)
        for strokeIndex in 0..<strokeCount {
            var points: [PKStrokePoint] = []
            points.reserveCapacity(pointsPerStroke)
            for pointIndex in 0..<pointsPerStroke {
                // 압축이 잘 안 되도록 좌표를 흩뜨린다. 값 자체에 의미는 없다.
                let seed = Double(strokeIndex &* 7919 &+ pointIndex &* 104_729)
                points.append(
                    PKStrokePoint(
                        location: CGPoint(x: seed.truncatingRemainder(dividingBy: 719.13),
                                          y: (seed * 0.618).truncatingRemainder(dividingBy: 991.37)),
                        timeOffset: Double(pointIndex) * 0.008,
                        size: CGSize(width: 2 + seed.truncatingRemainder(dividingBy: 3),
                                     height: 2 + seed.truncatingRemainder(dividingBy: 3)),
                        opacity: 1,
                        force: 0.5 + Double(pointIndex % 7) / 14,
                        azimuth: seed.truncatingRemainder(dividingBy: 3.14),
                        altitude: seed.truncatingRemainder(dividingBy: 1.57)
                    )
                )
            }
            strokes.append(
                PKStroke(ink: PKInk(.pen, color: .black),
                         path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000)))
            )
        }
        return PKDrawing(strokes: strokes).dataRepresentation()
    }
}

// MARK: - §10-1 · §10-2 마이그레이션

@Suite("스키마 V4 — V3 → V4 additive 마이그레이션 (설계 §10-1 · §10-2)")
struct DrawingSchemaV4MigrationTesting {

    private static let chapter = BibleChapter(title: .genesis, chapter: 1)
    private static let otherChapter = BibleChapter(title: .habakkuk, chapter: 2)

    // MARK: 스키마 정의 자체

    @Test("V4 는 버전 4.0.0 이고 V3 의 두 모델을 모두 유지한다 (§10-1 · §10-4)")
    func versionAndModels() {
        #expect(DrawingSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(DrawingSchemaV4.models.count == 2)
        // §10-4 — BiblePageDrawing 은 격하 대상이지만 Phase 1 에서 제거하지 않는다.
        let names = DrawingSchemaV4.models.map { "\($0)" }
        #expect(names.contains { $0.contains("BibleDrawing") })
        #expect(names.contains { $0.contains("BiblePageDrawing") })
    }

    @Test("마이그레이션 플랜은 V1~V4 4단계이고 V3 → V4 가 마지막이다")
    func migrationPlanShape() {
        #expect(DrawingDataMigrationPlan.schemas.count == 4)
        #expect(DrawingDataMigrationPlan.schemas.last?.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(DrawingDataMigrationPlan.stages.count == 3)
    }

    @Test("현재 별칭은 V4 를 가리킨다 — 스키마 구성이 한 곳에서 전파된다")
    func currentAliasPointsToV4() {
        #expect(BibleDrawing.self == DrawingSchemaV4.BibleDrawing.self)
        #expect(BiblePageDrawing.self == DrawingSchemaV4.BiblePageDrawing.self)
    }

    // MARK: 실제 마이그레이션 라운드트립

    @Test("V3 store 를 V4 로 다시 열면 모든 행과 필드가 보존되고 새 필드는 nil 이다")
    func v3StoreMigratesWithoutLoss() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        // given: V3 스키마로 store 를 만들고 데이터를 넣은 뒤 닫는다.
        let seeded = try Self.seedV3Store(at: directory)
        #expect(seeded.count == 3)

        // when: **같은 파일**을 V4 스키마 + 마이그레이션 플랜으로 다시 연다.
        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let migrated = try context.fetch(
            FetchDescriptor<BibleDrawing>(sortBy: [SortDescriptor(\.creationDate)])
        )

        // then: 행 수가 같다.
        #expect(migrated.count == seeded.count)

        for expected in seeded {
            let row = try #require(migrated.first { $0.id == expected.rowKey },
                                   "마이그레이션 후 \(expected.rowKey) 행이 사라졌다")

            // 기존 필드 전부 보존
            #expect(row.titleName == expected.titleName)
            #expect(row.titleChapter == expected.titleChapter)
            #expect(row.verse == expected.verse)
            #expect(row.isPresent == expected.isPresent)
            #expect(row.translation == .NKRV)
            #expect(row.creationDate == expected.creationDate)
            #expect(row.updateDate == expected.updateDate)

            // `.externalStorage` blob 이 바이트 단위로 살아 있다.
            #expect(row.lineData == expected.lineData)

            // ★ 자동 변환 금지 — drawingVersion 이 변하지 않았다 (§10-2)
            #expect(row.drawingVersion == expected.drawingVersion)

            // 새 필드는 nil. 마이그레이션이 채우지 않는다.
            #expect(row.layoutMetadataData == nil)
            #expect(row.rowUUID == nil)
        }
    }

    @Test("legacy 행의 drawingVersion 은 1 / nil 그대로 남는다 (§10-2 · §20-3 D8)")
    func legacyDrawingVersionIsUntouched() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        _ = try Self.seedV3Store(at: directory)
        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let migrated = try context.fetch(FetchDescriptor<BibleDrawing>())

        // D8 실측: 실기기 225행의 ZDRAWINGVERSION 은 전부 1 이었다.
        // 마이그레이션이 이 값을 2/3 으로 올리면 좌표 형식을 거짓말하게 된다.
        let versions = Set(migrated.map { $0.drawingVersion })
        #expect(versions == Set([1, nil]))
        #expect(migrated.allSatisfy { $0.drawingVersion != 2 && $0.drawingVersion != 3 })
    }

    @Test("실사용 legacy blob 은 마이그레이션 뒤에도 PencilKit 으로 그대로 디코드된다")
    func realLegacyBlobStillDecodes() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        _ = try Self.seedV3Store(at: directory)
        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)

        let verseNumber = 1
        let predicate = #Predicate<BibleDrawing> { $0.verse == verseNumber && $0.isPresent == true }
        let row = try #require(try context.fetch(FetchDescriptor<BibleDrawing>(predicate: predicate)).first)
        let data = try #require(row.lineData)

        #expect(data == RealLegacyLineData.data)
        let drawing = try PKDrawing(data: data)
        #expect(drawing.strokes.count == RealLegacyLineData.expectedStrokeCount)
    }

    @Test("외부저장으로 승격된 큰 blob 도 마이그레이션 뒤 바이트가 같다")
    func largeExternalStorageBlobSurvives() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        let seeded = try Self.seedV3Store(at: directory)
        let large = try #require(seeded.first { $0.verse == 7 })

        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let rowKey = large.rowKey
        let predicate = #Predicate<BibleDrawing> { $0.id == rowKey }
        let row = try #require(try context.fetch(FetchDescriptor<BibleDrawing>(predicate: predicate)).first)

        #expect(row.lineData == large.lineData)
        #expect((row.lineData?.count ?? 0) > 1_000_000)

        // 승격이 실제로 일어났는지 확인한다. 여기가 비면 blob 이 인라인으로 저장됐다는 뜻이고,
        // 그러면 이 테스트는 `.externalStorage` 경로를 검증하지 못한 것이다
        // (CoreData 의 승격 임계값이 올라간 경우 — fixture 크기를 키워야 한다).
        let externalFiles = V4StoreHarness.externalDataFiles(in: directory)
        #expect(externalFiles.isEmpty == false, "blob 이 외부저장으로 승격되지 않아 해당 경로를 검증하지 못했다")
        #expect(externalFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("BiblePageDrawing 행도 V4 로 그대로 넘어온다 (§10-4 — 이번에 제거하지 않는다)")
    func biblePageDrawingSurvives() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        _ = try Self.seedV3Store(at: directory)
        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)

        let pages = try context.fetch(FetchDescriptor<BiblePageDrawing>())
        let page = try #require(pages.first)
        #expect(pages.count == 1)
        #expect(page.titleName == Self.chapter.title.rawValue)
        #expect(page.titleChapter == Self.chapter.chapter)
        #expect(page.fullLineData == RealLegacyLineData.data)
    }

    // MARK: 새 필드

    @Test("새 필드는 V4 에서 쓰고 다시 읽을 수 있다 (layoutMetadataData 는 Codable blob)")
    func newFieldsRoundTrip() throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        let metadata = DrawingLayoutMetadata(
            baseWritingWidth: 360,
            baseWritingHeight: 132,
            baseUnderlineAnchors: [0, 44, 88],
            textLineRanges: [0..<12, 12..<25],
            layoutSignature: "sig-v4-roundtrip"
        )
        let rowUUID = UUID().uuidString
        let rowKey: String

        do {
            let container = try V4StoreHarness.openV4(at: directory)
            let context = ModelContext(container)
            let row = BibleDrawing(
                bibleTitle: Self.chapter,
                verse: 3,
                lineData: RealLegacyLineData.data,
                layoutMetadataData: try JSONEncoder().encode(metadata),
                rowUUID: rowUUID
            )
            // 좌표 형식의 단일 진실은 drawingVersion 이다 (§10-1).
            row.drawingVersion = 3
            rowKey = row.id
            context.insert(row)
            try context.save()
        }

        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let stored = try #require(
            try context.fetch(FetchDescriptor<BibleDrawing>(predicate: #Predicate { $0.id == rowKey })).first
        )
        #expect(stored.rowUUID == rowUUID)
        #expect(stored.drawingVersion == 3)
        let blob = try #require(stored.layoutMetadataData)
        #expect(try JSONDecoder().decode(DrawingLayoutMetadata.self, from: blob) == metadata)
    }

    @Test("신규 행은 rowUUID 를 발급받고, 선발급한 값을 넘기면 그 값을 쓴다 (§8-7)")
    func newRowsGetRowUUID() {
        let auto = BibleDrawing(bibleTitle: Self.chapter, verse: 1)
        #expect(auto.rowUUID != nil)
        #expect(UUID(uuidString: auto.rowUUID ?? "") != nil)

        // Phase 3 은 저장 전에 rowID 를 발급해 pending 큐 키로 쓴다. 그 값이 그대로 실려야 한다.
        let preIssued = UUID().uuidString
        let explicit = BibleDrawing(bibleTitle: Self.chapter, verse: 1, rowUUID: preIssued)
        #expect(explicit.rowUUID == preIssued)

        // 서로 다른 행은 서로 다른 UUID 를 받는다 (초 단위 business id 충돌 회피가 목적, §8-7).
        let other = BibleDrawing(bibleTitle: Self.chapter, verse: 1)
        #expect(auto.rowUUID != other.rowUUID)
    }

    @Test("SwiftData 가 쓰는 빈 이니셜라이저는 새 필드를 채우지 않는다")
    func emptyInitLeavesNewFieldsNil() {
        let row = BibleDrawing()
        #expect(row.layoutMetadataData == nil)
        #expect(row.rowUUID == nil)
    }

    // MARK: seeding

    /// V3 스키마로 store 를 만들어 데이터를 넣고 **닫는다.**
    ///
    /// 컨테이너를 이 함수 안에서만 살려 두는 것이 중요하다 — 같은 파일을 V4 로 다시 열어야 하므로.
    private static func seedV3Store(at directory: URL) throws -> [SeededV3Row] {
        let container = try ModelContainer(
            for: Schema([DrawingSchemaV3.BibleDrawing.self, DrawingSchemaV3.BiblePageDrawing.self]),
            configurations: ModelConfiguration(url: V4StoreHarness.storeURL(in: directory))
        )
        let context = ModelContext(container)

        // 1) 실사용 legacy blob, 대표 행, drawingVersion == 1
        let main = DrawingSchemaV3.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_740_000_000)
        )
        main.creationDate = Date(timeIntervalSince1970: 1_739_000_000)
        main.isPresent = true
        main.drawingVersion = 1

        // 2) 같은 절의 과거 회차. 획을 전부 지운 상태 — D8 에 실데이터가 없어 합성한다(§20-3).
        let history = DrawingSchemaV3.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: PKDrawing().dataRepresentation(),
            updateDate: Date(timeIntervalSince1970: 1_730_000_000)
        )
        history.id = "\(chapter.title.rawValue).\(chapter.chapter).1.1730000000"
        history.creationDate = Date(timeIntervalSince1970: 1_729_000_000)
        history.isPresent = false
        history.drawingVersion = 1

        // 3) drawingVersion 이 nil 인 행 + 외부저장 승격을 노린 큰 blob
        let unversioned = DrawingSchemaV3.BibleDrawing(
            bibleTitle: otherChapter,
            verse: 7,
            lineData: RealLegacyLineData.makeLargeDrawingData(),
            updateDate: Date(timeIntervalSince1970: 1_735_000_000)
        )
        unversioned.creationDate = Date(timeIntervalSince1970: 1_734_000_000)
        unversioned.isPresent = false
        unversioned.drawingVersion = nil

        let page = DrawingSchemaV3.BiblePageDrawing(
            bibleTitle: chapter,
            fullLineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_741_000_000)
        )

        let rows = [main, history, unversioned]
        rows.forEach { context.insert($0) }
        context.insert(page)
        try context.save()

        return rows.map {
            SeededV3Row(
                rowKey: $0.id,
                titleName: $0.titleName ?? "",
                titleChapter: $0.titleChapter ?? -1,
                verse: $0.verse ?? -1,
                isPresent: $0.isPresent ?? false,
                drawingVersion: $0.drawingVersion,
                creationDate: $0.creationDate ?? .distantPast,
                updateDate: $0.updateDate ?? .distantPast,
                lineData: $0.lineData ?? Data()
            )
        }
    }
}

// MARK: - §10-3 forward-only 안전망

/// **Phase 1 의 존재 이유** (설계 §10-3).
///
/// > "V4 저장소를 유지한 채 flag 를 껐을 때 기존 N Canvas 경로가 정상 동작해야 합니다.
/// > Phase 3 의 유일한 안전망이므로 Phase 1 배포 전에 이 경로를 확보합니다."
///
/// feature flag 는 아직 없으므로, 지금 시점의 등가 검증은 **"기존 코드 경로가 V4 저장소에서
/// 그대로 동작하는가"** 다. 저장소는 새로 만든 V4 가 아니라 **V3 에서 실제로 마이그레이션된 V4** 를 쓴다 —
/// flag off 상황이 정확히 그 상태이기 때문이다.
@Suite("§10-3 — 마이그레이션된 V4 저장소에서 기존 DrawingDatabase 경로")
struct LegacyPathOnV4StoreTesting {

    private static let chapter = BibleChapter(title: .genesis, chapter: 1)

    /// V3 로 씨를 뿌리고 V4 로 마이그레이션한 뒤, 그 컨테이너를 물린 `DrawingDatabase` 를 만든다.
    private static func makeMigratedDatabase(at directory: URL) throws -> DrawingDatabase {
        try seedV3(at: directory)
        let container = try V4StoreHarness.openV4(at: directory)
        return withDependencies {
            $0.createSwiftDataActor = SwiftDatabaseActor(modelContainer: container)
        } operation: {
            DrawingDatabase()
        }
    }

    private static func seedV3(at directory: URL) throws {
        let container = try ModelContainer(
            for: Schema([DrawingSchemaV3.BibleDrawing.self, DrawingSchemaV3.BiblePageDrawing.self]),
            configurations: ModelConfiguration(url: V4StoreHarness.storeURL(in: directory))
        )
        let context = ModelContext(container)

        // 1절 — 대표 행 + 과거 회차 (히스토리 유지, §8-7)
        let main = DrawingSchemaV3.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_740_000_000)
        )
        main.isPresent = true
        main.drawingVersion = 1

        let history = DrawingSchemaV3.BibleDrawing(
            bibleTitle: chapter,
            verse: 1,
            lineData: PKDrawing().dataRepresentation(),
            updateDate: Date(timeIntervalSince1970: 1_730_000_000)
        )
        history.id = "\(chapter.title.rawValue).\(chapter.chapter).1.1730000000"
        history.isPresent = false
        history.drawingVersion = 1

        // 2절 — 단일 행
        let second = DrawingSchemaV3.BibleDrawing(
            bibleTitle: chapter,
            verse: 2,
            lineData: RealLegacyLineData.data,
            updateDate: Date(timeIntervalSince1970: 1_738_000_000)
        )
        second.id = "\(chapter.title.rawValue).\(chapter.chapter).2.1738000000"
        second.isPresent = false
        second.drawingVersion = 1

        [main, history, second].forEach { context.insert($0) }
        try context.save()
    }

    // MARK: fetch 경로

    @Test("fetch(chapter:) 가 마이그레이션된 legacy 행을 그대로 읽는다")
    func fetchChapter() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let rows = try await database.fetch(chapter: Self.chapter)
        #expect(rows.count == 3)
        #expect(rows.map { $0.verse } == [1, 1, 2])
        #expect(rows.allSatisfy { $0.drawingVersion == 1 })
        #expect(rows.allSatisfy { $0.rowUUID == nil })
        #expect(rows.allSatisfy { $0.layoutMetadataData == nil })
    }

    @Test("fetchDrawings(chapter:verse:) + mainDrawing() 이 대표 행을 고른다")
    func fetchVerseAndMainDrawing() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let rows = try await database.fetchDrawings(chapter: Self.chapter, verse: 1)
        #expect(rows.count == 2)
        let main = try #require(rows.mainDrawing())
        #expect(main.isPresent == true)
        #expect(main.lineData == RealLegacyLineData.data)
    }

    @Test("fetchRecentDrawings / fetchDrawings(in:) / fetchDrawings(date:) 가 동작한다")
    func recentAndRangeQueries() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let recent = try await database.fetchRecentDrawings(limit: 2)
        #expect(recent.count == 2)
        #expect(recent.first?.updateDate == Date(timeIntervalSince1970: 1_740_000_000))

        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_735_000_000),
                                    end: Date(timeIntervalSince1970: 1_741_000_000))
        let inRange = try await database.fetchDrawings(in: interval)
        #expect(inRange.count == 2)

        let sameDay = try await database.fetchDrawings(date: Date(timeIntervalSince1970: 1_740_000_000))
        #expect((sameDay?.count ?? 0) >= 1)
    }

    // MARK: 쓰기 경로

    @Test("updateDrawings(requests:) 가 기존 legacy 행을 갱신하고 drawingVersion 을 건드리지 않는다 ★")
    func updateExistingRowKeepsDrawingVersion() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let newData = PKDrawing().dataRepresentation()
        let stamp = Date(timeIntervalSince1970: 1_742_000_000)
        await database.updateDrawings(requests: [
            DrawingUpdateRequest(chapter: Self.chapter, verse: 1, updateLineData: newData, updateDate: stamp)
        ])

        let rows = try await database.fetchDrawings(chapter: Self.chapter, verse: 1)
        let main = try #require(rows.mainDrawing())
        #expect(rows.count == 2, "회차 행이 늘어나면 안 된다 (§8-7)")
        #expect(main.lineData == newData)
        #expect(main.updateDate == stamp)
        // ★ 기존 경로의 쓰기는 좌표 형식을 바꾸지 않는다. legacy 는 legacy 로 남는다 (§10-2).
        #expect(main.drawingVersion == 1)
        #expect(main.layoutMetadataData == nil)
        // legacy 행에 rowUUID 를 소급 발급하지 않는다 (§8-7 비파괴).
        #expect(main.rowUUID == nil)
    }

    @Test("updateDrawings(requests:) 가 행이 없는 절에 새 행을 만든다")
    func createsRowForEmptyVerse() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let newData = RealLegacyLineData.data
        await database.updateDrawings(requests: [
            DrawingUpdateRequest(chapter: Self.chapter, verse: 9, updateLineData: newData)
        ])

        let rows = try await database.fetchDrawings(chapter: Self.chapter, verse: 9)
        let created = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(created.lineData == newData)
        // 신규 행은 rowUUID 를 갖는다. 좌표 형식은 아직 legacy 기본값이다 — 기록은 Phase 3 이다.
        #expect(created.rowUUID != nil)
        #expect(created.drawingVersion == 1)
    }

    @Test("N-Canvas 저장 요청이 legacy 행을 rowID로 갱신한다")
    func updateDrawingByRowRequest() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let rows = try await database.fetch(chapter: Self.chapter)
        let target = try #require(rows.first { $0.verse == 2 })
        let replacement = PKDrawing().dataRepresentation()
        target.lineData = replacement
        target.updateDate = Date(timeIntervalSince1970: 1_743_000_000)
        try await database.updateDrawing(request: LegacyDrawingSaveRequest(
            chapter: Self.chapter,
            verse: 2,
            rowID: BibleDrawingRowID(raw: target.rowKey),
            lineData: target.lineData,
            updateDate: target.updateDate,
            drawingVersion: target.drawingVersion,
            layoutMetadataData: target.layoutMetadataData
        ))

        let reloaded = try await database.fetchDrawings(chapter: Self.chapter, verse: 2)
        let stored = try #require(reloaded.first)
        #expect(stored.lineData == replacement)
        #expect(stored.drawingVersion == 1)
        #expect(stored.rowUUID == nil, "legacy 행에 UUID를 소급 발급하면 안 된다")
    }

    @Test("N-Canvas 신규 행은 선발급 rowUUID로 재시도해도 하나만 남는다")
    func insertDrawingPreservesPreissuedRowID() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)
        let rowID = BibleDrawingRowID.issue()
        let request = LegacyDrawingSaveRequest(
            chapter: Self.chapter,
            verse: 10,
            rowID: rowID,
            lineData: PKDrawing().dataRepresentation(),
            updateDate: Date(timeIntervalSince1970: 1_744_000_000),
            drawingVersion: 1,
            layoutMetadataData: nil
        )

        try await database.updateDrawing(request: request)
        try await database.updateDrawing(request: request)

        let rows = try await database.fetchDrawings(chapter: Self.chapter, verse: 10)
        #expect(rows.count == 1)
        #expect(rows.first?.rowUUID == rowID.raw)
        #expect(rows.first?.isPresent != true, "기존 N-Canvas 삽입 의미를 유지한다")
    }

    @Test("updatePresentDrawing 이 대표 행을 옮긴다 — 히스토리 복원 경로 (§8-7)")
    func updatePresentDrawing() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        let rows = try await database.fetchDrawings(chapter: Self.chapter, verse: 1)
        let older = try #require(rows.first { $0.isPresent != true })
        await database.updatePresentDrawing(chapter: Self.chapter, verse: 1, presentID: older.persistentModelID)

        let reloaded = try await database.fetchDrawings(chapter: Self.chapter, verse: 1)
        let present = reloaded.filter { $0.isPresent == true }
        #expect(present.count == 1)
        #expect(present.first?.persistentModelID == older.persistentModelID)
    }

    @Test("BiblePageDrawing upsert/fetch 경로가 V4 저장소에서 동작한다 (§10-4)")
    func pageDrawingPath() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let database = try Self.makeMigratedDatabase(at: directory)

        #expect(try await database.fetchPageDrawing(chapter: Self.chapter) == nil)

        await database.upsertPageDrawing(chapter: Self.chapter, fullLineData: RealLegacyLineData.data)
        let inserted = try #require(try await database.fetchPageDrawing(chapter: Self.chapter))
        #expect(inserted.fullLineData == RealLegacyLineData.data)

        let replacement = PKDrawing().dataRepresentation()
        await database.upsertPageDrawing(chapter: Self.chapter, fullLineData: replacement)
        let updated = try #require(try await database.fetchPageDrawing(chapter: Self.chapter))
        #expect(updated.fullLineData == replacement)
    }

    @Test("V4 로 마이그레이션한 store 를 앱과 같은 방식으로 다시 열어도 재마이그레이션이 없다")
    func reopeningMigratedStoreIsStable() async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }

        do {
            let database = try Self.makeMigratedDatabase(at: directory)
            await database.updateDrawings(requests: [
                DrawingUpdateRequest(chapter: Self.chapter, verse: 1,
                                     updateLineData: PKDrawing().dataRepresentation(),
                                     updateDate: Date(timeIntervalSince1970: 1_744_000_000))
            ])
        }

        // 앱 재기동에 해당한다. 이미 V4 인 store 를 다시 열어도 데이터가 그대로여야 한다.
        let container = try V4StoreHarness.openV4(at: directory)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<BibleDrawing>(sortBy: [SortDescriptor(\.verse)]))
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.drawingVersion == 1 })
        let main = try #require(rows.first { $0.verse == 1 && $0.isPresent == true })
        #expect(main.updateDate == Date(timeIntervalSince1970: 1_744_000_000))
    }
}
