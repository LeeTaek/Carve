//
//  LegacyRowLinkageReader.swift
//  Domain
//
//  C14 ② — legacy 행의 미러링 대응을 **세 값**으로 판정하는 사설 판독기 (정책 §12-6 C14, 테스트 계획 §3-3 SEP-1).
//
//  공개 API(`NSPersistentCloudKitContainer.recordID(for:)`)는 미러링을 켜지 않은 저장소에서 대응이 있는 행에도 nil 을 준다(F34).
//  그래서 저장소의 사설 표 `ANSCKRECORDMETADATA` 를 **읽기 전용 SQLite** 로 읽는다. 사설 표에 기대는 만큼 판독 자체를 검증한다 —
//  구조 · 엔티티 구분 · 행 수 재확인 · 저장소 계정 식별과의 교차 확인 중 하나라도 어긋나면 결과는 「알 수 없음」 이고, 그 실행은
//  미러링을 연결하지 않는다(연결 보류, D2). 판독은 **사본에서** 한다(F35).
//
//      ZENTITYID = `Z_PRIMARYKEY.Z_ENT` · ZENTITYPK = 그 엔티티 표의 `Z_PK` (2026-09-21 실제 저장소에서 확인, F34)
//
//  **검증한 범위 밖은 「알 수 없음」 이다** — OS 주 버전 · 저장소 모델 버전 · 엔티티(대응 관측이 실제 저장소에서 있었던 것)를 판독기가
//  들고 있고, 범위 밖이면 행을 읽기 전에 보류로 끝낸다.
//

import CarveToolkit
import Foundation
import SQLite3

/// 1.3.0 이 남긴 legacy 엔티티 3종 (정책 §12-6 C14 ⑦, D5).
public enum LegacyEntity: String, CaseIterable, Codable, Hashable, Sendable {
    case bibleDrawing = "BibleDrawing"
    case biblePageDrawing = "BiblePageDrawing"
    case favoriteVerse = "FavoriteVerse"

    /// SQLite 표 이름. Core Data 는 `Z` + 대문자 엔티티 이름을 쓴다.
    var table: String { "Z" + rawValue.uppercased() }

    /// 행을 알아볼 business ID 칸. 판정에는 쓰지 않고 보존 · 표시용 식별에만 쓴다(C14 ②).
    var rowIDColumn: String {
        switch self {
        case .bibleDrawing, .biblePageDrawing: "ZID"
        case .favoriteVerse: "ZFAVORITEID"
        }
    }
}

/// 행 하나의 판정 — 세 값 (C14 ②).
public enum LegacyRowLinkage: Equatable, Sendable {
    /// 그 행의 미러링 레코드 대응을 읽었다. 분리하지 않는다.
    case linked
    /// 판독이 검증을 통과했고 그 행에 대응이 없다. 분리 대상이다.
    case verifiedUnlinked
    /// 판독 실패 · 검증 불통과 · 모호. 분리하지 않고 연결을 보류한다.
    case unknown
}

/// 저장소 안에서 legacy 행 하나를 가리키는 값. **엔티티 구분을 넣는다** — 기본 키가 같아도 다른 엔티티면 다른 행이다.
public struct LegacyRowIdentity: Hashable, Codable, Sendable {
    public var entity: LegacyEntity
    /// 그 엔티티 표의 `Z_PK`.
    public var primaryKey: Int64
    /// business ID(`id` · `favoriteID`). 없을 수 있다.
    public var rowID: String?

    public init(entity: LegacyEntity, primaryKey: Int64, rowID: String? = nil) {
        self.entity = entity
        self.primaryKey = primaryKey
        self.rowID = rowID
    }
}

/// 「알 수 없음」 의 까닭. 어느 것이든 **연결 보류**다 — 까닭은 안내 · 기록 · 재시도 판단에만 쓴다.
public enum LegacyLinkageUnknownReason: Error, Hashable, Sendable {
    /// 판독기를 검증하지 않은 OS 주 버전이다.
    case unvalidatedEnvironment(osMajor: Int)
    /// 검증하지 않은 저장소 모델이다(모르는 스키마 · 메타데이터를 읽지 못함 · 파일 없음 포함).
    case unvalidatedModel(String)
    /// 사본을 뜨지 못했거나 읽기 전용으로 열지 못했다.
    case cannotOpen(String)
    /// SQLite 무결성 검사를 통과하지 못했다.
    case integrityCheckFailed(String)
    case tableMissing(String)
    case columnMissing(table: String, column: String)
    /// 질의 준비 · 실행이 실패했다.
    case queryFailed(table: String, message: String)
    /// `Z_PRIMARYKEY` 에 legacy 엔티티가 없다(표는 있는데 엔티티 등록이 없거나, 최소 엔티티인 `BibleDrawing` 이 없다).
    case entityMissing(LegacyEntity)
    /// 표의 행이 든 `Z_ENT` 가 `Z_PRIMARYKEY` 의 값과 다르다 — 엔티티 구분을 믿을 수 없다.
    case entityIDMismatch(LegacyEntity, offendingRows: Int)
    /// 행을 읽은 뒤 다시 센 수가 다르다 — 읽는 사이에 바뀌었거나 일부만 읽었다.
    case rowCountChanged(LegacyEntity)
    /// 대응이 `Z_PRIMARYKEY` 에 없는 엔티티를 가리킨다.
    case unknownEntityID(Int64)
    /// 같은 (엔티티, 기본 키) 에 대응이 둘 이상이다.
    case duplicateCorrespondence(entityID: Int64, primaryKey: Int64)
    /// 대응 항목은 있는데 레코드 이름이 없다 — 대응인지 아닌지 말할 수 없다.
    case ambiguousCorrespondence(entityID: Int64, primaryKey: Int64)
    /// 저장소 계정 식별과 대응이 서로 맞지 않는다(식별이 없는데 대응이 있다).
    case identityInconsistent(String)
    /// 대응 관측이 실제 저장소에서 아직 없었던 엔티티에 행 · 대응이 있다.
    case unvalidatedEntity(LegacyEntity)
}

/// 판독 결과 한 벌.
public struct LegacyRowLinkageReading: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// legacy 행이 모두 대응이 있다(행이 없어도 여기다).
        case allLinked
        /// 검증된 대응 없음 행이 있다. 목록은 엔티티 · 기본 키 순이다.
        case hasVerifiedUnlinked([LegacyRowIdentity])
        /// 판독 실패 · 검증 불통과. **연결 보류.**
        case unknown(LegacyLinkageUnknownReason)
    }

    public var verdict: Verdict
    /// 판독기 버전. 작업 기록에 남긴다.
    public var readerVersion: Int
    /// 행별 판정. 「알 수 없음」 으로 끝났으면 비어 있을 수 있다.
    public var rows: [LegacyRowIdentity: LegacyRowLinkage]
    /// 대응은 있지만 아직 올리지 않은 행 수(`ZNEEDSUPLOAD`).
    public var needsUploadCount: Int
    /// 행은 없는데 대응만 남은 항목 수(F37 의 고아). 판정을 바꾸지 않고 기록만 한다.
    public var orphanCorrespondenceCount: Int
    /// 저장소 메타데이터에 계정 식별 키가 있는가(F33). **값은 읽지 않는다.**
    public var hasAccountIdentityKeys: Bool
    /// 저장소 메타데이터 키 수.
    public var metadataKeyCount: Int
    /// 저장소 모델(가려낸 결과).
    public var storeModel: String

    public var linkedCount: Int { rows.values.filter { $0 == .linked }.count }
    public var unlinkedCount: Int { rows.values.filter { $0 == .verifiedUnlinked }.count }

    public var isUnknown: Bool {
        if case .unknown = verdict { return true }
        return false
    }

    /// 로그 · 기록용 요약. 계정 식별 원문 · 레코드 이름은 들지 않는다.
    public var summary: String {
        var text = "판정 \(verdictText) · 판독기 v\(readerVersion) · 모델 \(storeModel)"
        text += " · 대응 있음 \(linkedCount) · 검증된 대응 없음 \(unlinkedCount) · 업로드 대기 \(needsUploadCount) · 고아 대응 \(orphanCorrespondenceCount)"
        text += " · 메타데이터 키 \(metadataKeyCount)개(계정 식별 \(hasAccountIdentityKeys ? "있음" : "없음"))"
        return text
    }

    private var verdictText: String {
        switch verdict {
        case .allLinked: "모두 대응 있음"
        case .hasVerifiedUnlinked(let rows): "검증된 대응 없음 \(rows.count)행"
        case .unknown(let reason): "알 수 없음(\(reason))"
        }
    }
}

/// C14 ② 의 판독기. 값(`validated…`)이 곧 검증 범위다 — 넓히려면 실제 저장소 관측(테스트 계획 §5-1)을 먼저 기록한다.
public struct LegacyRowLinkageReader: Sendable {
    /// 판독기 자체의 버전. 읽는 표 · 열 · 규칙이 바뀌면 올린다.
    public static let version = 1

    /// 판독기를 검증한 OS 주 버전. SEP-0 ~ SEP-2 는 iOS 26 시뮬레이터에서 수행했다(2026-09-21).
    public var validatedOSMajors: Set<Int> = [26]
    /// 판독기를 검증한 저장소 스키마 주 버전 — 1.3.0 의 V3(마이그레이션 전)와 현재 V6(마이그레이션 뒤). SEP-1 F39.
    public var validatedSchemaMajors: Set<Int> = [3, 6]
    /// `ZENTITYID = Z_ENT` 를 **실제 미러링 저장소에서 관측한** 엔티티. 관측이 없는 엔티티에 행 · 대응이 있으면 「알 수 없음」 이다.
    /// `BibleDrawing` 은 SEP-0 ~ SEP-2(F34 · F36 ~ F40). 나머지는 관측을 기록한 뒤 넣는다(테스트 계획 §3-3 SEP-1 통과 기준).
    public var validatedEntities: Set<LegacyEntity> = [.bibleDrawing]
    /// 지금 OS 주 버전. 시험이 바꾼다.
    public var osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    public init() {}

    // MARK: - 진입

    /// 저장소 **원본**을 주면 사본을 뜬 뒤 그 사본을 판독한다. 원본 파일은 열지 않는다(F35).
    /// - Parameters:
    ///   - storeURL: 저장소 본 파일. `-wal` · `-shm` 이 있으면 함께 뜬다.
    ///   - scratchDirectory: 사본을 둘 곳. 생략하면 임시 폴더에 두고 판독 뒤 지운다.
    public func judge(storeAt storeURL: URL, scratchDirectory: URL? = nil, fileManager: FileManager = .default) -> LegacyRowLinkageReading {
        let directory = scratchDirectory ?? fileManager.temporaryDirectory.appendingPathComponent("linkage-\(UUID().uuidString)", isDirectory: true)
        defer { if scratchDirectory == nil { try? fileManager.removeItem(at: directory) } }
        let copy: URL
        do {
            copy = try Self.copyStoreFiles(from: storeURL, into: directory, fileManager: fileManager)
        } catch {
            return Self.unknown(.cannotOpen("사본을 뜨지 못했다: \(error)"))
        }
        return judge(copyAt: copy)
    }

    /// 이미 떠 둔 **사본**을 판독한다. 사본이라도 쓰지 않는다 — 읽기 전용으로만 연다.
    public func judge(copyAt url: URL) -> LegacyRowLinkageReading {
        guard validatedOSMajors.contains(osMajor) else {
            return Self.unknown(.unvalidatedEnvironment(osMajor: osMajor))
        }
        let kind = LocalStoreLoader.storeKind(at: url)
        guard case .known(let version) = kind, validatedSchemaMajors.contains(version.major) else {
            return Self.unknown(.unvalidatedModel("\(kind)"))
        }
        let model = "V\(version.major)"

        var handle: OpaquePointer?
        let uri = "file:\(url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            return Self.unknown(.cannotOpen(message), model: model)
        }
        defer { sqlite3_close(db) }

        do {
            return try read(SQLiteReadOnly(db: db), model: model)
        } catch let reason as LegacyLinkageUnknownReason {
            return Self.unknown(reason, model: model)
        } catch {
            return Self.unknown(.queryFailed(table: "-", message: "\(error)"), model: model)
        }
    }

    // MARK: - 판독

    private func read(_ sql: SQLiteReadOnly, model: String) throws -> LegacyRowLinkageReading {
        let integrity = try sql.strings("PRAGMA integrity_check", table: "integrity_check")
        guard integrity == ["ok"] else {
            throw LegacyLinkageUnknownReason.integrityCheckFailed(integrity.prefix(3).joined(separator: " / "))
        }

        let tables = Set(try sql.strings("SELECT name FROM sqlite_master WHERE type = 'table'", table: "sqlite_master"))
        try require(tables, "Z_PRIMARYKEY", columns: ["Z_ENT", "Z_NAME"], sql)
        try require(tables, "Z_METADATA", columns: ["Z_VERSION"], sql)
        try require(tables, "ANSCKRECORDMETADATA", columns: Self.correspondenceColumns, sql)
        try require(tables, "ANSCKMETADATAENTRY", columns: ["ZKEY"], sql)

        // 엔티티 등록 — 이름 → Z_ENT. 미러링 · 이력 엔티티(16001 ~)도 함께 들어 있다.
        var entityIDs: [String: Int64] = [:]
        try sql.rows("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY WHERE Z_NAME IS NOT NULL", table: "Z_PRIMARYKEY") { statement in
            entityIDs[sql.text(statement, 1) ?? ""] = sqlite3_column_int64(statement, 0)
        }
        let knownIDs = Set(entityIDs.values)

        // legacy 엔티티 — 등록과 표가 함께 있어야 한다. 표만 있거나 등록만 있으면 구분을 믿을 수 없다.
        var present: [LegacyEntity: Int64] = [:]
        for entity in LegacyEntity.allCases {
            let registered = entityIDs[entity.rawValue]
            let hasTable = tables.contains(entity.table)
            switch (registered, hasTable) {
            case (.some(let id), true): present[entity] = id
            case (.none, false): continue
            case (.none, true): throw LegacyLinkageUnknownReason.entityMissing(entity)
            case (.some, false): throw LegacyLinkageUnknownReason.tableMissing(entity.table)
            }
        }
        guard present[.bibleDrawing] != nil else { throw LegacyLinkageUnknownReason.entityMissing(.bibleDrawing) }

        // 행 — 엔티티마다 Z_PK · Z_ENT · business ID 를 읽고, Z_ENT 를 등록값과 맞춰 본 뒤 다시 센다.
        var rowsByEntity: [LegacyEntity: [LegacyRowIdentity]] = [:]
        for (entity, id) in present.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            try require(tables, entity.table, columns: ["Z_PK", "Z_ENT", entity.rowIDColumn], sql)
            var identities: [LegacyRowIdentity] = []
            var offending = 0
            try sql.rows("SELECT Z_PK, Z_ENT, \(entity.rowIDColumn) FROM \(entity.table) ORDER BY Z_PK", table: entity.table) { statement in
                if sqlite3_column_int64(statement, 1) != id { offending += 1 }
                identities.append(LegacyRowIdentity(entity: entity, primaryKey: sqlite3_column_int64(statement, 0), rowID: sql.text(statement, 2)))
            }
            guard offending == 0 else { throw LegacyLinkageUnknownReason.entityIDMismatch(entity, offendingRows: offending) }
            let recount = try sql.integers("SELECT count(*) FROM \(entity.table)", table: entity.table).first ?? -1
            guard recount == identities.count else { throw LegacyLinkageUnknownReason.rowCountChanged(entity) }
            rowsByEntity[entity] = identities
        }

        // 대응 — 미러링이 아는 (엔티티, 기본 키). 레코드 이름이 있어야 대응이다.
        let legacyByID = Dictionary(uniqueKeysWithValues: present.map { ($0.value, $0.key) })
        var correspondences: [Correspondence] = []
        var seen: Set<PairKey> = []
        var needsUpload = 0
        try sql.rows("SELECT \(Self.correspondenceColumns.joined(separator: ", ")) FROM ANSCKRECORDMETADATA", table: "ANSCKRECORDMETADATA") { statement in
            correspondences.append(Correspondence(
                entityID: sqlite3_column_int64(statement, 0),
                primaryKey: sqlite3_column_int64(statement, 1),
                hasRecordName: (sql.text(statement, 2)?.isEmpty == false),
                needsUpload: sqlite3_column_int64(statement, 3) != 0
            ))
        }
        var linked: Set<LegacyRowIdentity> = []
        var orphans = 0
        for item in correspondences {
            guard knownIDs.contains(item.entityID) else { throw LegacyLinkageUnknownReason.unknownEntityID(item.entityID) }
            let key = PairKey(entityID: item.entityID, primaryKey: item.primaryKey)
            guard seen.insert(key).inserted else {
                throw LegacyLinkageUnknownReason.duplicateCorrespondence(entityID: item.entityID, primaryKey: item.primaryKey)
            }
            guard let entity = legacyByID[item.entityID] else { continue }   // 새 엔티티(버전 · 기준점)의 대응은 이 판정 밖이다.
            guard item.hasRecordName else {
                throw LegacyLinkageUnknownReason.ambiguousCorrespondence(entityID: item.entityID, primaryKey: item.primaryKey)
            }
            if item.needsUpload { needsUpload += 1 }
            if let row = rowsByEntity[entity]?.first(where: { $0.primaryKey == item.primaryKey }) {
                linked.insert(row)
            } else {
                orphans += 1
            }
        }

        // 저장소 계정 식별과의 교차 확인 — 키 이름만 본다(F33).
        let keys = try sql.strings("SELECT ZKEY FROM ANSCKMETADATAENTRY WHERE ZKEY IS NOT NULL", table: "ANSCKMETADATAENTRY")
        let hasIdentity = keys.contains { $0.contains("CKIdentity") }
        let legacyCorrespondences = correspondences.filter { legacyByID[$0.entityID] != nil }.count
        if !hasIdentity, legacyCorrespondences > 0 {
            throw LegacyLinkageUnknownReason.identityInconsistent("계정 식별 키 없이 대응 \(legacyCorrespondences)개")
        }

        // 검증 범위 밖 엔티티 — 행이나 대응이 하나라도 있으면 판정하지 않는다.
        for entity in LegacyEntity.allCases where !validatedEntities.contains(entity) {
            let hasRows = (rowsByEntity[entity]?.isEmpty == false)
            let hasCorrespondence = present[entity].map { id in correspondences.contains { $0.entityID == id } } ?? false
            if hasRows || hasCorrespondence { throw LegacyLinkageUnknownReason.unvalidatedEntity(entity) }
        }

        var rows: [LegacyRowIdentity: LegacyRowLinkage] = [:]
        var unlinked: [LegacyRowIdentity] = []
        for entity in LegacyEntity.allCases {
            for row in rowsByEntity[entity] ?? [] {
                if linked.contains(row) {
                    rows[row] = .linked
                } else {
                    rows[row] = .verifiedUnlinked
                    unlinked.append(row)
                }
            }
        }
        return LegacyRowLinkageReading(
            verdict: unlinked.isEmpty ? .allLinked : .hasVerifiedUnlinked(unlinked),
            readerVersion: Self.version,
            rows: rows,
            needsUploadCount: needsUpload,
            orphanCorrespondenceCount: orphans,
            hasAccountIdentityKeys: hasIdentity,
            metadataKeyCount: keys.count,
            storeModel: model
        )
    }

    // MARK: - 도우미

    private static let correspondenceColumns = ["ZENTITYID", "ZENTITYPK", "ZCKRECORDNAME", "ZNEEDSUPLOAD", "ZNEEDSCLOUDDELETE", "ZNEEDSLOCALDELETE"]

    private struct Correspondence {
        var entityID: Int64
        var primaryKey: Int64
        var hasRecordName: Bool
        var needsUpload: Bool
    }

    private struct PairKey: Hashable {
        var entityID: Int64
        var primaryKey: Int64
    }

    private func require(_ tables: Set<String>, _ table: String, columns: [String], _ sql: SQLiteReadOnly) throws {
        guard tables.contains(table) else { throw LegacyLinkageUnknownReason.tableMissing(table) }
        var found: Set<String> = []
        try sql.rows("PRAGMA table_info(\"\(table)\")", table: table) { statement in
            if let name = sql.text(statement, 1) { found.insert(name) }
        }
        for column in columns where !found.contains(column) {
            throw LegacyLinkageUnknownReason.columnMissing(table: table, column: column)
        }
    }

    private static func unknown(_ reason: LegacyLinkageUnknownReason, model: String = "-") -> LegacyRowLinkageReading {
        LegacyRowLinkageReading(
            verdict: .unknown(reason), readerVersion: version, rows: [:], needsUploadCount: 0, orphanCorrespondenceCount: 0,
            hasAccountIdentityKeys: false, metadataKeyCount: 0, storeModel: model
        )
    }

    /// 저장소 한 벌(본 파일 · `-wal` · `-shm`)을 복사한다. 원본은 읽기만 한다. 외부 저장 blob 은 판정에 필요 없어 뜨지 않는다.
    static func copyStoreFiles(from storeURL: URL, into directory: URL, fileManager: FileManager) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(storeURL.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
        }
        return destination
    }
}

/// 읽기 전용 연결 위의 얇은 질의 도우미. 준비 · 실행 실패를 `queryFailed` 로 올린다 — 조용히 빈 결과로 두지 않는다.
private struct SQLiteReadOnly {
    let db: OpaquePointer

    func rows(_ query: String, table: String, _ body: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LegacyLinkageUnknownReason.queryFailed(table: table, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                body(statement)
            } else if step == SQLITE_DONE {
                return
            } else {
                throw LegacyLinkageUnknownReason.queryFailed(table: table, message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func strings(_ query: String, table: String) throws -> [String] {
        var result: [String] = []
        try rows(query, table: table) { statement in
            if let value = text(statement, 0) { result.append(value) }
        }
        return result
    }

    func integers(_ query: String, table: String) throws -> [Int64] {
        var result: [Int64] = []
        try rows(query, table: table) { statement in result.append(sqlite3_column_int64(statement, 0)) }
        return result
    }

    func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}
