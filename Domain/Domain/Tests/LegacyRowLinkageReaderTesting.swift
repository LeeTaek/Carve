//
//  LegacyRowLinkageReaderTesting.swift
//  DomainTest
//
//  C14 ② 판독기 — 세 값 판정과 **음성 시험** (정책 §12-6 C14, 테스트 계획 §3-3 SEP-1).
//
//  정상 표본만 통과하는 것으로 끝내지 않는다. 손상 · 표 없음 · 열 이름 다름 · 엔티티 구분 어긋남 · 일부 행만 모호 · 교차 확인 불일치 ·
//  검증 범위 밖(OS · 모델 · 엔티티)을 **실제 파일**로 만들어, 어느 것이든 「알 수 없음」(연결 보류)으로 끝나는지 본다.
//
//  표본은 앱 스키마로 실제 저장소를 만들고, 미러링 사설 표는 실제 저장소(2026-09-22 시뮬레이터 dut 의 `Carve.dev.sqlite`)에서 읽은
//  DDL 그대로 SQL 로 만든다. 계정 식별 키는 **이름만** 넣는다 — 값은 판독기가 읽지 않는다.
//

import Foundation
import SQLite3
import SwiftData
import Testing

@testable import Domain

// MARK: - 표본

/// 실제 파일 표본. 만들고 손질하는 방법을 한곳에 둔다.
enum LinkageFixture {
    static let chapter = BibleChapter(title: .genesis, chapter: 1)

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("linkage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 앱 스키마(V6) 저장소 — `BibleDrawing` 절 1 · 2 · 3 을 넣고 닫는다. 미러링 표를 붙이고, 계정 식별 키는 아직 없다(로그인한 적 없는 모양, F33).
    static func makeV6Store(in directory: URL, page: Bool = false, favorite: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("Carve.sqlite")
        try seedV6(at: url, page: page, favorite: favorite)
        try ensureMirroringTables(url)
        return url
    }

    /// 1.3.0 모양(V3) 저장소 — `BibleDrawing` 절 1 · 2 · 3.
    static func makeV3Store(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("Carve.sqlite")
        try seedV3(at: url)
        try ensureMirroringTables(url)
        return url
    }

    private static func seedV6(at url: URL, page: Bool, favorite: Bool) throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        for verse in 1...3 {
            context.insert(BibleDrawing(bibleTitle: chapter, verse: verse, lineData: RealLegacyLineData.data, rowUUID: "row-\(verse)"))
        }
        if page {
            context.insert(BiblePageDrawing(bibleTitle: chapter, fullLineData: RealLegacyLineData.data))
        }
        if favorite {
            context.insert(FavoriteVerse(chapter: chapter, verse: 1, translation: .NKRV, sentence: "태초에", lineData: RealLegacyLineData.data, createdDate: Date()))
        }
        try context.save()
    }

    private static func seedV3(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema(DrawingSchemaV3.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        for verse in 1...3 {
            context.insert(DrawingSchemaV3.BibleDrawing(bibleTitle: chapter, verse: verse, lineData: RealLegacyLineData.data))
        }
        try context.save()
    }

    /// 미러링 사설 표 — 실제 저장소의 DDL 그대로. 이미 있으면 그대로 둔다.
    static func ensureMirroringTables(_ url: URL) throws {
        try exec(url, """
        CREATE TABLE IF NOT EXISTS ANSCKRECORDMETADATA ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZENTITYID INTEGER, ZENTITYPK INTEGER, \
        ZLASTEXPORTEDTRANSACTIONNUMBER INTEGER, ZNEEDSCLOUDDELETE INTEGER, ZNEEDSLOCALDELETE INTEGER, ZNEEDSUPLOAD INTEGER, ZPENDINGEXPORTCHANGETYPENUMBER INTEGER, \
        ZPENDINGEXPORTTRANSACTIONNUMBER INTEGER, ZENCODEDRECORDASSET INTEGER, ZRECORDZONE INTEGER, ZSYSTEMFIELDSASSET INTEGER, ZCKRECORDNAME VARCHAR );
        CREATE UNIQUE INDEX IF NOT EXISTS Z_NSCKRecordMetadata_UNIQUE_entityId_entityPK ON ANSCKRECORDMETADATA (ZENTITYID COLLATE BINARY ASC, ZENTITYPK COLLATE BINARY ASC);
        CREATE UNIQUE INDEX IF NOT EXISTS Z_NSCKRecordMetadata_UNIQUE_ckRecordName_recordZone \
        ON ANSCKRECORDMETADATA (ZCKRECORDNAME COLLATE BINARY ASC, ZRECORDZONE COLLATE BINARY ASC);
        CREATE TABLE IF NOT EXISTS ANSCKMETADATAENTRY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZBOOLVALUENUM INTEGER, ZINTEGERVALUE INTEGER, \
        ZDATEVALUE TIMESTAMP, ZKEY VARCHAR, ZSTRINGVALUE VARCHAR, ZTRANSFORMEDVALUE BLOB );
        INSERT OR IGNORE INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) VALUES (17009, 'NSCKMetadataEntry', 0, 0), (17012, 'NSCKRecordMetadata', 0, 0);
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZTRANSFORMEDVALUE, ZKEY) SELECT 17009, 1, X'01', 'PFCloudKitMetadataClientVersionHashesKey' \
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'PFCloudKitMetadataClientVersionHashesKey');
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZINTEGERVALUE, ZKEY) SELECT 17009, 1, 1, 'PFCloudKitMetadataFrameworkVersionKey' \
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'PFCloudKitMetadataFrameworkVersionKey');
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZTRANSFORMEDVALUE, ZKEY) SELECT 17009, 1, X'01', 'PFCloudKitMetadataModelVersionHashesKey' \
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'PFCloudKitMetadataModelVersionHashesKey');
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZBOOLVALUENUM, ZKEY) SELECT 17009, 1, 0, 'PFCloudKitMetadataNeedsMetadataMigrationKey' \
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'PFCloudKitMetadataNeedsMetadataMigrationKey');
        """)
    }

    /// 계정 식별 키 3개를 **이름만** 붙인다(F33). 로그인한 적 있는 저장소의 모양이다.
    static func addIdentityKeys(_ url: URL) throws {
        try exec(url, """
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZSTRINGVALUE, ZKEY)
        SELECT 17009, 1, 'fixture-user-record', 'NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey'
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey');
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZBOOLVALUENUM, ZKEY)
        SELECT 17009, 1, 1, 'NSCloudKitMirroringDelegateCheckedCKIdentityDefaultsKey'
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'NSCloudKitMirroringDelegateCheckedCKIdentityDefaultsKey');
        INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZTRANSFORMEDVALUE, ZKEY)
        SELECT 17009, 1, X'01', 'NSCloudKitMirroringDelegateLastHistoryTokenKey'
        WHERE NOT EXISTS (SELECT 1 FROM ANSCKMETADATAENTRY WHERE ZKEY = 'NSCloudKitMirroringDelegateLastHistoryTokenKey');
        """)
    }

    /// (엔티티, 기본 키) 에 대응을 붙인다. 레코드 이름은 UUID 다 — 계정 식별이 아니다.
    static func link(_ url: URL, entity: LegacyEntity, primaryKey: Int64, recordName: String? = UUID().uuidString, needsUpload: Bool = false) throws {
        let name = recordName.map { "'\($0)'" } ?? "NULL"
        try exec(url, """
        INSERT INTO ANSCKRECORDMETADATA (Z_ENT, Z_OPT, ZENTITYID, ZENTITYPK, ZNEEDSUPLOAD, ZNEEDSCLOUDDELETE, ZNEEDSLOCALDELETE, ZCKRECORDNAME)
        VALUES (17012, 1, (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = '\(entity.rawValue)'), \(primaryKey), \(needsUpload ? 1 : 0), 0, 0, \(name));
        """)
    }

    /// 사설 표에 엔티티 ID 를 직접 적어 대응을 붙인다 — 모르는 엔티티 · 중복 같은 어긋난 모양을 만들 때.
    static func linkRaw(_ url: URL, entityID: Int64, primaryKey: Int64) throws {
        try exec(url, """
        INSERT INTO ANSCKRECORDMETADATA (Z_ENT, Z_OPT, ZENTITYID, ZENTITYPK, ZNEEDSUPLOAD, ZNEEDSCLOUDDELETE, ZNEEDSLOCALDELETE, ZCKRECORDNAME)
        VALUES (17012, 1, \(entityID), \(primaryKey), 0, 0, 0, '\(UUID().uuidString)');
        """)
    }

    static func entityID(_ url: URL, _ entity: LegacyEntity) throws -> Int64 {
        try scalar(url, "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = '\(entity.rawValue)'")
    }

    /// 본 파일에 모두 내려 쓴 뒤 **마지막 페이지부터 절반**을 쓰레기로 덮는다 — 열리기는 하지만 무결성 검사에 걸리거나 메타데이터를 읽지 못한다.
    static func corrupt(_ url: URL) throws {
        try exec(url, "PRAGMA wal_checkpoint(TRUNCATE);")
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        let pageSize = 4096
        let firstPage = max(1, (size / pageSize) / 2)
        try handle.seek(toOffset: UInt64(firstPage * pageSize))
        try handle.write(contentsOf: Data(repeating: 0xAB, count: size - firstPage * pageSize))
    }

    static func exec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            throw FixtureError.open(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_close(db) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "?"
            sqlite3_free(message)
            throw FixtureError.exec(text)
        }
    }

    static func scalar(_ url: URL, _ sql: String) throws -> Int64 {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            throw FixtureError.open(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw FixtureError.exec(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FixtureError.exec("no row") }
        return sqlite3_column_int64(statement, 0)
    }

    enum FixtureError: Error { case open(String), exec(String) }
}

// MARK: - 시험

@Suite("C14 ② 판독기 — 세 값 판정과 음성 시험")
struct LegacyRowLinkageReaderTesting {

    private func withStore(page: Bool = false, favorite: Bool = false, _ body: (URL) throws -> Void) throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(try LinkageFixture.makeV6Store(in: directory, page: page, favorite: favorite))
    }

    private func reason(_ reading: LegacyRowLinkageReading) -> LegacyLinkageUnknownReason? {
        if case .unknown(let reason) = reading.verdict { return reason }
        return nil
    }

    private var reader: LegacyRowLinkageReader {
        var reader = LegacyRowLinkageReader()
        reader.osMajor = 26
        return reader
    }

    // MARK: 세 값

    @Test("모든 행에 대응이 있으면 「모두 대응 있음」 — 계정 식별 있음 · V6")
    func allLinked() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)

            let reading = reader.judge(storeAt: url)

            #expect(reading.verdict == .allLinked)
            #expect(reading.linkedCount == 3 && reading.unlinkedCount == 0)
            #expect(reading.hasAccountIdentityKeys && reading.metadataKeyCount == 7)
            #expect(reading.storeModel == "V6" && reading.readerVersion == LegacyRowLinkageReader.version)
        }
    }

    @Test("대응 없는 행만 「검증된 대응 없음」 으로 — 엔티티 · 기본 키 · business ID 가 붙는다")
    func mixedRowsListTheUnlinkedOnes() throws {
        try withStore { url in
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 1)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 3)
            try LinkageFixture.addIdentityKeys(url)

            let reading = reader.judge(storeAt: url)

            guard case .hasVerifiedUnlinked(let unlinked) = reading.verdict else { Issue.record("판정이 다르다: \(reading.summary)"); return }
            #expect(unlinked.count == 1 && unlinked.first?.entity == .bibleDrawing && unlinked.first?.primaryKey == 2)
            #expect(unlinked.first?.rowID?.hasPrefix("1-01Genesis.txt.1.") == true)   // 기본 키와 절 번호의 대응은 삽입 순서에 달려 단정하지 않는다
            #expect(reading.rows[LegacyRowIdentity(entity: .bibleDrawing, primaryKey: 1, rowID: unlinked.first?.rowID)] == nil)
            #expect(reading.rows.values.filter { $0 == .linked }.count == 2)
        }
    }

    @Test("로그인한 적 없는 저장소(식별 키 없음 · 대응 0)는 모든 행이 「검증된 대응 없음」")
    func neverSignedInStoreIsVerifiedUnlinked() throws {
        try withStore { url in
        let reading = reader.judge(storeAt: url)

        guard case .hasVerifiedUnlinked(let unlinked) = reading.verdict else { Issue.record("판정이 다르다: \(reading.summary)"); return }
        #expect(unlinked.map(\.primaryKey) == [1, 2, 3])
        #expect(!reading.hasAccountIdentityKeys && reading.metadataKeyCount == 4)
        #expect(reading.metadataEntryCount == 4 && reading.duplicateMetadataKeyCount == 0)
        #expect(Set(reading.metadataKeys) == LegacyRowLinkageReader.unaccountedV3MetadataKeys)
        #expect(reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false)
        }
    }

    @Test("실제 iOS 18 V3에서 새로 보인 migration marker 는 지원하지 않는 metadata 모양으로 남는다")
    func migrationMarkerIsRecordedAsUnrecognizedMetadata() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZBOOLVALUENUM, ZKEY) VALUES (17009, 1, 1, 'PFCloudKitMetadataModelMigratorMigrationBeganCommitKey');")

            let reading = reader.judge(storeAt: url)

            #expect(reading.unlinkedCount == 3)
            #expect(!reading.metadataValueProfileComplete)
            #expect(!Set(reading.metadataKeys).isSubset(of: LegacyRowLinkageReader.unaccountedV3MetadataKeys))
        }
    }

    @Test("legacy 행이 하나도 없으면 「모두 대응 있음」(빈 저장소)")
    func emptyStoreIsAllLinked() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DELETE FROM ZBIBLEDRAWING;")
            #expect(reader.judge(storeAt: url).verdict == .allLinked)
        }
    }

    @Test("행이 없는 고아 대응(F37)은 판정을 바꾸지 않고 수만 남는다")
    func orphanCorrespondenceIsCountedOnly() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 99)
            try LinkageFixture.addIdentityKeys(url)

            let reading = reader.judge(storeAt: url)

            #expect(reading.verdict == .allLinked && reading.orphanCorrespondenceCount == 1)
        }
    }

    @Test("대응은 있지만 미전송인 행(ZNEEDSUPLOAD)은 「대응 있음」 이고 따로 센다")
    func needsUploadRowsAreLinked() throws {
        try withStore { url in
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 1, needsUpload: true)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 2)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 3)
            try LinkageFixture.addIdentityKeys(url)

            let reading = reader.judge(storeAt: url)

            #expect(reading.verdict == .allLinked && reading.needsUploadCount == 1)
        }
    }

    @Test("1.3.0 모양(V3) 저장소도 마이그레이션 전에 판정된다")
    func v3StoreIsJudgedBeforeMigration() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try LinkageFixture.makeV3Store(in: directory)

        let reading = reader.judge(storeAt: url)

        guard case .hasVerifiedUnlinked(let unlinked) = reading.verdict else { Issue.record("판정이 다르다: \(reading.summary)"); return }
        #expect(unlinked.count == 3 && reading.storeModel == "V3")
    }

    @Test("원본을 주면 사본에서 판정하고, 원본 파일 한 벌은 바이트 그대로다(F35)")
    func originalStoreIsNotTouched() throws {
        try withStore { url in
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 1)
            try LinkageFixture.addIdentityKeys(url)
            let before = fingerprints(url)

            let reading = reader.judge(storeAt: url)

            #expect(!reading.isUnknown)
            #expect(fingerprints(url) == before)
        }
    }

    @Test("검증한 엔티티 집합에 든 엔티티의 행은 판정되고, 들지 않으면 「알 수 없음」")
    func validatedEntitySetGatesOtherEntities() throws {
        try withStore(favorite: true) { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.link(url, entity: .favoriteVerse, primaryKey: 1)
            try LinkageFixture.addIdentityKeys(url)

            var narrow = reader
            narrow.validatedEntities = [.bibleDrawing]
            #expect(reason(narrow.judge(storeAt: url)) == .unvalidatedEntity(.favoriteVerse))

            let reading = reader.judge(storeAt: url)
            #expect(reading.verdict == .allLinked && reading.linkedCount == 4)
            #expect(reading.rows.keys.contains { $0.entity == .favoriteVerse && $0.primaryKey == 1 })
        }
    }

    @Test("기본 검증 집합은 legacy 3종 전부다(v2, F51) — 장 전체 필기 · 즐겨찾기의 대응 없는 행도 「검증된 대응 없음」 으로 판정한다")
    func defaultValidatedSetCoversAllLegacyEntities() throws {
        #expect(LegacyRowLinkageReader().validatedEntities == Set(LegacyEntity.allCases))
        #expect(LegacyRowLinkageReader.version == 4)
        try withStore(page: true, favorite: true) { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)

            let reading = reader.judge(storeAt: url)

            guard case .hasVerifiedUnlinked(let unlinked) = reading.verdict else { Issue.record("판정이 다르다: \(reading.summary)"); return }
            #expect(Set(unlinked.map(\.entity)) == [.biblePageDrawing, .favoriteVerse])
            #expect(reading.linkedCount == 3)
        }
    }

    // MARK: 도우미

    private func fingerprints(_ url: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if let data = try? Data(contentsOf: file) { result[file.lastPathComponent] = data }
        }
        return result
    }
}

// MARK: - 음성 — 어느 것이든 연결 보류

extension LegacyRowLinkageReaderTesting {

    @Test("검증 밖 OS 라도 legacy 행이 없으면 연결한다 — 분리할 것이 없다(새 설치 · 로그아웃해 비워진 저장소)")
    func unvalidatedOSWithoutRowsConnects() throws {
        var elsewhere = reader
        elsewhere.osMajor = 18
        try withStore { url in
            try LinkageFixture.exec(url, "DELETE FROM ZBIBLEDRAWING;")
            #expect(elsewhere.judge(storeAt: url).verdict == .allLinked)
        }
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fresh = directory.appendingPathComponent("Carve.sqlite")
        _ = try ModelContainer(for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self, configurations: ModelConfiguration(url: fresh, cloudKitDatabase: .none))
        let reading = elsewhere.judge(storeAt: fresh)
        #expect(reading.verdict == .allLinked && !reading.mirroringAttached)
    }

    @Test("검증하지 않은 iOS 17 주 버전이면 legacy 행이 있을 때 사설 표를 해석하기 전에 「알 수 없음」")
    func unvalidatedOSIsUnknown() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            var elsewhere = reader
            elsewhere.osMajor = 17

            #expect(reason(elsewhere.judge(storeAt: url)) == .unvalidatedEnvironment(osMajor: 17))
        }
    }

    @Test("iOS 18의 V3 migration 표식 의미가 미확인이라 보류하고 미지 OS 19도 보류한다")
    func unverifiedOlderOSIsEvidenceBounded() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)

            var ios18 = reader
            ios18.osMajor = 18
            #expect(reason(ios18.judge(storeAt: url)) == .unvalidatedEnvironment(osMajor: 18))

            var ios19 = reader
            ios19.osMajor = 19
            #expect(reason(ios19.judge(storeAt: url)) == .unvalidatedEnvironment(osMajor: 19))
        }
    }

    @Test("기본 판독기는 실행 중인 OS 를 따른다 — 검증 범위 밖 OS 에서는 저장소를 읽기 전에 「알 수 없음」")
    func defaultReaderFollowsTheRunningOS() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            let running = LegacyRowLinkageReader()
            let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            #expect(running.osMajor == major)

            let reading = running.judge(storeAt: url)

            if running.validatedOSMajors.contains(major) {
                #expect(reading.verdict == .allLinked)
            } else {
                #expect(reason(reading) == .unvalidatedEnvironment(osMajor: major))
                #expect(reading.rows.isEmpty)
            }
        }
    }

    @Test("파일이 없거나 모르는 모델이면 「알 수 없음」")
    func missingOrUnknownModelIsUnknown() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("nothing.sqlite")
        #expect(reason(reader.judge(storeAt: missing)) == .unvalidatedModel("missing"))

        // 아는 스키마라도 검증한 버전 밖이면 보류한다 — V6 를 검증 목록에서 빼 본다.
        let url = try LinkageFixture.makeV6Store(in: directory)
        var narrow = reader
        narrow.validatedSchemaMajors = [3]
        #expect(reason(narrow.judge(storeAt: url)) == .unvalidatedModel("known(6.0.0)"))
    }

    @Test("손상된 파일은 「알 수 없음」 — 열리지 않거나 무결성 검사에 걸린다")
    func corruptedFileIsUnknown() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            try LinkageFixture.corrupt(url)

            let reading = reader.judge(storeAt: url)

            #expect(reading.isUnknown, "손상된 파일인데 판정했다: \(reading.summary)")
            switch reason(reading) {
            case .integrityCheckFailed, .cannotOpen, .unvalidatedModel, .queryFailed: break
            default: Issue.record("손상의 까닭이 아니다: \(reading.summary)")
            }
        }
    }

    @Test("미러링 표가 하나도 없고 legacy 행도 없으면 「모두 대응 있음」 — 새로 설치해 저장소를 처음 만든 실행")
    func freshStoreWithoutMirroringTablesConnects() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        _ = try ModelContainer(for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))

        let reading = reader.judge(storeAt: url)

        #expect(reading.verdict == .allLinked && !reading.mirroringAttached)
        #expect(reading.summary.contains("미러링 표 없음"))
    }

    @Test("미러링 표가 하나도 없는데 legacy 행이 있으면 「알 수 없음」 — 관측한 적 없는 모양")
    func rowsWithoutMirroringTablesAreUnknown() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DROP TABLE ANSCKRECORDMETADATA; DROP TABLE ANSCKMETADATAENTRY;")
            #expect(reason(reader.judge(storeAt: url)) == .mirroringNotAttached(legacyRows: 3))
        }
    }

    @Test("대응 표가 없으면 「알 수 없음」")
    func missingCorrespondenceTableIsUnknown() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DROP TABLE ANSCKRECORDMETADATA;")
            #expect(reason(reader.judge(storeAt: url)) == .tableMissing("ANSCKRECORDMETADATA"))
        }
    }

    @Test("legacy 행이 없으면 미러링 표의 모양이 달라도 연결한다 — 해석할 것이 없다(미래 OS 가 표를 바꿔도 새 설치가 막히지 않게)")
    func changedMirroringSchemaWithoutRowsConnects() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DELETE FROM ZBIBLEDRAWING; ALTER TABLE ANSCKRECORDMETADATA RENAME COLUMN ZCKRECORDNAME TO ZRECORDNAME;")
            #expect(reader.judge(storeAt: url).verdict == .allLinked)
        }
    }

    @Test("대응 표의 열 이름이 다르면 「알 수 없음」")
    func renamedColumnIsUnknown() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "ALTER TABLE ANSCKRECORDMETADATA RENAME COLUMN ZCKRECORDNAME TO ZRECORDNAME;")
            #expect(reason(reader.judge(storeAt: url)) == .columnMissing(table: "ANSCKRECORDMETADATA", column: "ZCKRECORDNAME"))
        }
    }

    @Test("저장소 메타데이터 표가 없으면 「알 수 없음」 — 교차 확인을 할 수 없다")
    func missingMetadataEntryTableIsUnknown() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DROP TABLE ANSCKMETADATAENTRY;")
            #expect(reason(reader.judge(storeAt: url)) == .tableMissing("ANSCKMETADATAENTRY"))
        }
    }

    @Test("엔티티 등록은 있는데 표가 없거나, 표는 있는데 등록이 없으면 「알 수 없음」")
    func entityRegistrationAndTableMustAgree() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DROP TABLE ZBIBLEPAGEDRAWING;")
            #expect(reason(reader.judge(storeAt: url)) == .tableMissing("ZBIBLEPAGEDRAWING"))
        }
        try withStore { url in
            try LinkageFixture.exec(url, "DELETE FROM Z_PRIMARYKEY WHERE Z_NAME = 'BiblePageDrawing';")
            #expect(reason(reader.judge(storeAt: url)) == .entityMissing(.biblePageDrawing))
        }
        try withStore { url in
            try LinkageFixture.exec(url, "DELETE FROM Z_PRIMARYKEY WHERE Z_NAME = 'BibleDrawing'; DROP TABLE ZBIBLEDRAWING;")
            #expect(reason(reader.judge(storeAt: url)) == .entityMissing(.bibleDrawing))
        }
    }

    @Test("표의 행이 든 Z_ENT 가 등록값과 다르면 「알 수 없음」 — 엔티티 구분을 믿을 수 없다")
    func rowEntityIDMismatchIsUnknown() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            try LinkageFixture.exec(url, "UPDATE ZBIBLEDRAWING SET Z_ENT = 9 WHERE Z_PK = 2;")

            #expect(reason(reader.judge(storeAt: url)) == .entityIDMismatch(.bibleDrawing, offendingRows: 1))
        }
    }

    @Test("대응이 모르는 엔티티를 가리키면 「알 수 없음」")
    func unknownEntityIDIsUnknown() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            try LinkageFixture.linkRaw(url, entityID: 42, primaryKey: 1)

            #expect(reason(reader.judge(storeAt: url)) == .unknownEntityID(42))
        }
    }

    @Test("같은 (엔티티, 기본 키) 에 대응이 둘이면 「알 수 없음」")
    func duplicateCorrespondenceIsUnknown() throws {
        try withStore { url in
            let id = try LinkageFixture.entityID(url, .bibleDrawing)
            try LinkageFixture.exec(url, "DROP INDEX Z_NSCKRecordMetadata_UNIQUE_entityId_entityPK;")
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.linkRaw(url, entityID: id, primaryKey: 2)
            try LinkageFixture.addIdentityKeys(url)

            #expect(reason(reader.judge(storeAt: url)) == .duplicateCorrespondence(entityID: id, primaryKey: 2))
        }
    }

    @Test("일부 행만 모호(대응 항목은 있는데 레코드 이름이 없음)해도 저장소 전체가 「알 수 없음」")
    func partiallyAmbiguousStoreIsUnknown() throws {
        try withStore { url in
            let id = try LinkageFixture.entityID(url, .bibleDrawing)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 1)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 2, recordName: nil)
            try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 3)
            try LinkageFixture.addIdentityKeys(url)

            #expect(reason(reader.judge(storeAt: url)) == .ambiguousCorrespondence(entityID: id, primaryKey: 2))
        }
    }

    @Test("계정 식별 키가 없는데 대응이 있으면 교차 확인 불일치 — 「알 수 없음」")
    func correspondenceWithoutIdentityIsUnknown() throws {
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }

            #expect(reason(reader.judge(storeAt: url)) == .identityInconsistent("계정 식별 키 없이 대응 3개"))
        }
    }

    @Test("대응 관측이 없는 엔티티(검증 집합 밖)에 행이 있으면 「알 수 없음」")
    func unvalidatedEntityRowsAreUnknown() throws {
        var narrow = reader
        narrow.validatedEntities = [.bibleDrawing]
        try withStore(page: true) { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)

            #expect(reason(narrow.judge(storeAt: url)) == .unvalidatedEntity(.biblePageDrawing))
        }
        // 행은 없고 대응만 그 엔티티를 가리켜도 같다.
        try withStore { url in
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.link(url, entity: .favoriteVerse, primaryKey: 7)
            try LinkageFixture.addIdentityKeys(url)

            #expect(reason(narrow.judge(storeAt: url)) == .unvalidatedEntity(.favoriteVerse))
        }
    }

    @Test("「알 수 없음」 은 행 목록을 주지 않는다 — 부분 결과로 분리하지 못하게")
    func unknownReadingCarriesNoRows() throws {
        try withStore { url in
            try LinkageFixture.exec(url, "DROP TABLE ANSCKRECORDMETADATA;")
            let reading = reader.judge(storeAt: url)
            #expect(reading.isUnknown && reading.rows.isEmpty && reading.linkedCount == 0 && reading.unlinkedCount == 0)
        }
    }

}
