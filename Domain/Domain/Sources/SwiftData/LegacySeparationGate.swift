//
//  LegacySeparationGate.swift
//  Domain
//
//  C14 — 1.3.0 무계정 legacy 행 분리의 **게이트** (정책 §12-6 C14 ① ~ ④, 테스트 계획 §3-3).
//
//  미러링(`.private`)을 연결하기 **직전**에 저장소를 판정한다. 판정은 사본에서 세 값으로 한다(`LegacyRowLinkageReader`).
//
//  | 판정 | 이 게이트가 하는 일 |
//  |---|---|
//  | 모두 대응 있음 | 연결한다 |
//  | 알 수 없음 | **연결 보류** — 저장소는 CloudKit 없이 열고, 쓰기 · 전체 삭제를 막는다(③ · D2 · D6) |
//  | 검증된 대응 없음 행이 있다 | 그 행들의 **분리본**과 **분리 작업 기록**을 보존 영역에 남기고(④), 연결 보류 |
//
//  **저장소에서 행을 지우는 파괴적 분리는 아직 연결하지 않았다** — 「최우선 — 파괴적 분리 구현 전」 관문의 미확인 항목(삽입 이력 없는 무대응 행 ·
//  legacy 3종의 대응 · 제품 삭제 경로 · 서버 확인, 2026-09-22 검토)이 채워지기 전이다. 그동안은 대응 없는 행이 있으면 보류한다 —
//  연결하면 그 행이 지금 계정으로 올라가기 때문이다(F40).
//

import CarveToolkit
import CryptoKit
import Foundation
import SQLite3

import Dependencies

// MARK: - 보류

/// 연결을 보류한 까닭 (C14 ③).
public enum LegacySeparationHoldReason: Hashable, Sendable {
    /// 판정이 「알 수 없음」 이다.
    case linkageUnknown(LegacyLinkageUnknownReason)
    /// 검증된 대응 없음 행이 있다. 파괴적 분리가 연결되기 전이라 분리본 · 기록만 남기고 연결하지 않는다.
    case unlinkedRowsAwaitSeparation(count: Int)
    /// 분리본 · 작업 기록을 남기지 못했다.
    case preservationFailed(String)
}

/// 이번 실행의 연결 보류. 자동으로 풀리지 않는다 — 다음 실행이 다시 판정한다(D4).
public struct LegacySeparationHold: Hashable, Sendable {
    public var reason: LegacySeparationHoldReason
    public var readerVersion: Int
    /// 남긴 분리 작업 기록의 ID. 없으면 기록을 남기지 않았다.
    public var jobID: String?

    public init(reason: LegacySeparationHoldReason, readerVersion: Int = LegacyRowLinkageReader.version, jobID: String? = nil) {
        self.reason = reason
        self.readerVersion = readerVersion
        self.jobID = jobID
    }

    /// 조건부 연결 동의(D7)를 낼 수 있는 상태인가 — 분리 삭제를 시작하지 않았고 보존에 실패하지 않았을 때만.
    /// 2.0.0 은 아직 동의 화면을 내지 않는다. 값만 둔다.
    public var allowsConditionalConsent: Bool {
        switch reason {
        case .linkageUnknown: true
        case .unlinkedRowsAwaitSeparation, .preservationFailed: false
        }
    }
}

/// 이번 실행의 보류 상태를 두는 곳. 컨테이너를 만들 때 한 번 정하고, 편집 환경 · 설정이 읽는다.
///
/// **소유 근거가 나중에 생겨도 풀리지 않는다**(C14 ③) — 이 값은 실행 중에 nil 로 돌아가지 않는다.
public final class LegacySeparationHoldState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: LegacySeparationHold?

    public init(hold: LegacySeparationHold? = nil) {
        value = hold
    }

    public var hold: LegacySeparationHold? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }

    public var isHeld: Bool { hold != nil }
}

extension LegacySeparationHoldState: DependencyKey {
    /// 앱 수명 동안 하나다 — 컨테이너를 만드는 곳과 읽는 곳이 같은 값을 본다.
    public static let liveValue = LegacySeparationHoldState()
    /// 시험마다 새 값. 보류를 흉내 내려면 `withDependencies` 로 바꾼다.
    public static var testValue: LegacySeparationHoldState { LegacySeparationHoldState() }
}

public extension DependencyValues {
    /// 이번 실행의 C14 연결 보류.
    var legacySeparationHoldState: LegacySeparationHoldState {
        get { self[LegacySeparationHoldState.self] }
        set { self[LegacySeparationHoldState.self] = newValue }
    }
}

// MARK: - 분리본 · 작업 기록

/// 분리한 행 하나의 사본 — 그 표의 **모든 열**을 그대로 든다(원형 보존, C14 ⑦). 외부 저장으로 빠진 blob 은 안에 넣는다.
public struct LegacySeparatedRow: Codable, Equatable, Sendable {
    public enum Value: Codable, Equatable, Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
    }

    public var identity: LegacyRowIdentity
    public var columns: [String: Value]
    /// 모든 열의 지문. 파일을 다시 읽어 이 값이 나와야 보존된 것이다.
    public var contentFingerprint: String

    /// `BibleDrawing` 의 내용 지문(`VerseContentFingerprint`) — 가져오기(⑥)가 버전과 맞출 때 쓴다. 다른 엔티티는 nil.
    public var verseContentFingerprint: String? {
        guard identity.entity == .bibleDrawing else { return nil }
        return VerseContentFingerprint.make(lineData: blob("ZLINEDATA"), drawingVersion: integer("ZDRAWINGVERSION").map(Int.init), layoutMetadataBlob: blob("ZLAYOUTMETADATADATA"))
    }

    public func blob(_ column: String) -> Data? {
        if case .blob(let data)? = columns[column] { return data }
        return nil
    }

    public func integer(_ column: String) -> Int64? {
        if case .integer(let value)? = columns[column] { return value }
        return nil
    }

    public func text(_ column: String) -> String? {
        if case .text(let value)? = columns[column] { return value }
        return nil
    }

    /// 열 이름 순으로 종류 · 길이 · 바이트를 이어 붙인 SHA-256.
    static func fingerprint(of columns: [String: Value]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("carve.separatedRow/1".utf8))
        for (name, value) in columns.sorted(by: { $0.key < $1.key }) {
            hasher.update(data: Data("|\(name)=".utf8))
            switch value {
            case .null: hasher.update(data: Data("n".utf8))
            case .integer(let number): hasher.update(data: Data("i\(number)".utf8))
            case .real(let number): hasher.update(data: Data("r\(number.bitPattern)".utf8))
            case .text(let string): hasher.update(data: Data("t\(string.utf8.count):".utf8)); hasher.update(data: Data(string.utf8))
            case .blob(let data): hasher.update(data: Data("b\(data.count):".utf8)); hasher.update(data: data)
            }
        }
        return "sr1-" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 분리 작업 기록 (C14 ④). C11 의 삭제 작업과 같은 형식 — 대상 · 보존 확인 · 삭제 진행 · 완료 표식. **삭제보다 먼저** 내구성 있게 쓴다.
public struct LegacySeparationJob: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public struct Target: Codable, Equatable, Sendable {
        public var identity: LegacyRowIdentity
        public var contentFingerprint: String
        public var verseContentFingerprint: String?
        /// 분리본을 쓰고 다시 읽어 지문이 맞았다.
        public var preserved: Bool
        /// `rows/` 아래 파일 이름.
        public var fileName: String
    }

    public struct Deletion: Codable, Equatable, Sendable {
        public var started = false
        public var completed = false
        public init() {}
    }

    public var formatVersion: Int
    /// 저장소 UUID · 대상 · 지문으로 정한 결정적 ID — 같은 대상이면 같은 작업이다(멱등).
    public var jobID: String
    /// 저장소의 `Z_UUID`. 계정 식별이 아니다.
    public var storeUUID: String
    public var readerVersion: Int
    public var createdAt: Date
    public var targets: [Target]
    public var deletion: Deletion
    /// 완료 표식 — 삭제 · 색인까지 끝나야 참이다. 지금 단계에서는 늘 거짓이다.
    public var completed: Bool

    public var allPreserved: Bool { targets.allSatisfy(\.preserved) }
}

/// 분리본 · 작업 기록의 자리와 쓰기 · 읽기. 보존 영역 안이라 이 기기의 전체 삭제가 함께 지운다(C11 단계 ④).
public struct LegacySeparationRecordStore: Sendable {
    public enum Failure: Error, Equatable {
        case cannotReadRow(LegacyRowIdentity, String)
        case externalDataMissing(String)
        case writeFailed(String)
        case verifyFailed(LegacyRowIdentity)
    }

    public let area: PreservationArea
    private let fileManager: FileManager
    private static let jobFileName = "job.json"
    private static let rowsDirectoryName = "rows"
    private static let partialSuffix = ".partial"
    /// 외부 저장(`.externalStorage`)이 되는 열 — 값 앞에 `0x01`(안에 둠) · `0x02`(파일 이름) 이 붙는다.
    private static let externalColumns: Set<String> = ["ZLINEDATA", "ZLAYOUTMETADATADATA", "ZFULLLINEDATA"]

    public init(area: PreservationArea, fileManager: FileManager = .default) {
        self.area = area
        self.fileManager = fileManager
    }

    public var directory: URL { area.separationDirectory }

    // MARK: 읽기

    /// 남아 있는 작업 기록. 완료된 것(`.partial` 이 아닌 폴더에 `job.json` 이 있는 것)만.
    public func jobs() throws -> [LegacySeparationJob] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try children
            .filter { !$0.lastPathComponent.hasSuffix(Self.partialSuffix) }
            .compactMap { folder -> LegacySeparationJob? in
                let file = folder.appendingPathComponent(Self.jobFileName)
                guard fileManager.fileExists(atPath: file.path) else { return nil }
                return try Self.decoder.decode(LegacySeparationJob.self, from: Data(contentsOf: file))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 그 작업의 분리본들. 파일을 하나라도 읽지 못하면 던진다 — 없는 것으로 치지 않는다.
    public func rows(of job: LegacySeparationJob) throws -> [LegacySeparatedRow] {
        try job.targets.map { target in
            let file = directory.appendingPathComponent(job.jobID).appendingPathComponent(Self.rowsDirectoryName).appendingPathComponent(target.fileName)
            let row = try Self.decoder.decode(LegacySeparatedRow.self, from: Data(contentsOf: file))
            guard LegacySeparatedRow.fingerprint(of: row.columns) == row.contentFingerprint, row.contentFingerprint == target.contentFingerprint else {
                throw Failure.verifyFailed(target.identity)
            }
            return row
        }
    }

    // MARK: 쓰기

    /// 대상 행들의 분리본을 쓰고 확인한 뒤 작업 기록을 남긴다. 같은 대상 · 같은 내용이면 이미 있는 기록을 그대로 돌려준다(멱등).
    /// - Parameters:
    ///   - targets: 판정에서 「검증된 대응 없음」 이 된 행들.
    ///   - copyURL: 판정에 쓴 **사본** — 행 내용은 여기서 읽는다.
    ///   - storeURL: 원본 저장소 — 외부 저장 blob 파일은 원본 옆 `_SUPPORT` 에 있다.
    public func preserve(
        targets: [LegacyRowIdentity],
        readingFrom copyURL: URL,
        externalDataBeside storeURL: URL,
        readerVersion: Int,
        now: Date = Date()
    ) throws -> LegacySeparationJob {
        let rows = try targets.map { try readRow($0, from: copyURL, storeURL: storeURL) }
        let storeUUID = (try? Self.storeUUID(of: copyURL)) ?? "-"
        let jobID = Self.jobID(storeUUID: storeUUID, rows: rows)

        if let existing = try? existingJob(jobID), existing.allPreserved, (try? self.rows(of: existing)) != nil {
            return existing
        }

        removeAbandonedStaging()
        let staging = directory.appendingPathComponent(jobID + Self.partialSuffix, isDirectory: true)
        let final = directory.appendingPathComponent(jobID, isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try? fileManager.removeItem(at: final)
        do {
            try fileManager.createDirectory(at: staging.appendingPathComponent(Self.rowsDirectoryName, isDirectory: true), withIntermediateDirectories: true)
        } catch {
            throw Failure.writeFailed("\(error)")
        }

        var recorded: [LegacySeparationJob.Target] = []
        for row in rows {
            let fileName = "\(row.identity.entity.rawValue)-\(row.identity.primaryKey).json"
            let file = staging.appendingPathComponent(Self.rowsDirectoryName).appendingPathComponent(fileName)
            do {
                try DurableFile.write(try Self.encoder.encode(row), to: file)
            } catch {
                throw Failure.writeFailed("\(error)")
            }
            // 보존 확인 — 다시 읽어 지문이 같아야 한다(C14 ① 「보존의 기준」).
            guard let reread = try? Self.decoder.decode(LegacySeparatedRow.self, from: Data(contentsOf: file)),
                  reread == row, LegacySeparatedRow.fingerprint(of: reread.columns) == row.contentFingerprint else {
                throw Failure.verifyFailed(row.identity)
            }
            recorded.append(LegacySeparationJob.Target(
                identity: row.identity, contentFingerprint: row.contentFingerprint, verseContentFingerprint: row.verseContentFingerprint,
                preserved: true, fileName: fileName
            ))
        }

        let job = LegacySeparationJob(
            formatVersion: LegacySeparationJob.formatVersion, jobID: jobID, storeUUID: storeUUID, readerVersion: readerVersion,
            createdAt: now, targets: recorded, deletion: LegacySeparationJob.Deletion(), completed: false
        )
        do {
            try DurableFile.write(try Self.encoder.encode(job), to: staging.appendingPathComponent(Self.jobFileName))
            try fileManager.moveItem(at: staging, to: final)
            try? DurableFile.flush(directory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw Failure.writeFailed("\(error)")
        }
        return job
    }

    private func existingJob(_ jobID: String) throws -> LegacySeparationJob? {
        let file = directory.appendingPathComponent(jobID).appendingPathComponent(Self.jobFileName)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        return try Self.decoder.decode(LegacySeparationJob.self, from: Data(contentsOf: file))
    }

    private func removeAbandonedStaging() {
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent.hasSuffix(Self.partialSuffix) {
            try? fileManager.removeItem(at: child)
        }
    }

    static func jobID(storeUUID: String, rows: [LegacySeparatedRow]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("carve.separationJob/1|\(storeUUID)".utf8))
        for row in rows.sorted(by: { ($0.identity.entity.rawValue, $0.identity.primaryKey) < ($1.identity.entity.rawValue, $1.identity.primaryKey) }) {
            hasher.update(data: Data("|\(row.identity.entity.rawValue):\(row.identity.primaryKey):\(row.contentFingerprint)".utf8))
        }
        return String(hasher.finalize().map { String(format: "%02x", $0) }.joined().prefix(24))
    }

    // MARK: 행 읽기 (읽기 전용 SQLite)

    private func readRow(_ identity: LegacyRowIdentity, from copyURL: URL, storeURL: URL) throws -> LegacySeparatedRow {
        var handle: OpaquePointer?
        guard sqlite3_open_v2("file:\(copyURL.path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw Failure.cannotReadRow(identity, message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let query = "SELECT * FROM \(identity.entity.table) WHERE Z_PK = ?"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure.cannotReadRow(identity, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, identity.primaryKey)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw Failure.cannotReadRow(identity, "행이 없다") }

        let support = RawStoreSnapshot.supportDirectory(for: storeURL).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        var columns: [String: LegacySeparatedRow.Value] = [:]
        for index in 0 ..< sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER: columns[name] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT: columns[name] = .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT: columns[name] = .text(String(cString: sqlite3_column_text(statement, index)))
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(statement, index)
                let count = Int(sqlite3_column_bytes(statement, index))
                let raw = bytes.map { Data(bytes: $0, count: count) } ?? Data()
                columns[name] = .blob(try Self.resolveExternal(raw, column: name, in: support))
            default: columns[name] = .null
            }
        }
        return LegacySeparatedRow(identity: identity, columns: columns, contentFingerprint: LegacySeparatedRow.fingerprint(of: columns))
    }

    /// 외부 저장 열의 값 — `0x01` + 값이면 안에 둔 것, `0x02` + 파일 이름 + `NUL` 이면 `_EXTERNAL_DATA` 의 파일이다.
    private static func resolveExternal(_ raw: Data, column: String, in support: URL) throws -> Data {
        guard externalColumns.contains(column), let first = raw.first else { return raw }
        switch first {
        case 0x01:
            return raw.dropFirst()
        case 0x02:
            guard let name = String(bytes: raw.dropFirst().prefix { $0 != 0 }, encoding: .utf8), name.isEmpty == false else {
                throw Failure.externalDataMissing("이름을 읽지 못함")
            }
            guard let data = try? Data(contentsOf: support.appendingPathComponent(name)) else { throw Failure.externalDataMissing(name) }
            return data
        default:
            return raw
        }
    }

    private static func storeUUID(of copyURL: URL) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open_v2("file:\(copyURL.path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw Failure.writeFailed("store uuid")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT Z_UUID FROM Z_METADATA LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure.writeFailed("store uuid")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw Failure.writeFailed("store uuid") }
        return String(cString: text)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public extension PreservationArea {
    /// 분리본 · 분리 작업 기록(C14 ④)의 위치. 보존 영역 안이므로 이 기기의 전체 삭제가 함께 지운다.
    var separationDirectory: URL { storeDirectory.appendingPathComponent("separation", isDirectory: true) }
}

// MARK: - 게이트

/// 연결 직전의 판정 · 보존 · 결정 (C14 ①). 저장소 파일은 읽기만 한다 — 판정은 사본에서, 보존은 보존 영역에.
public struct LegacySeparationGate: Sendable {
    public enum Decision: Equatable, Sendable {
        /// 미러링을 연결한다.
        case connect(LegacyRowLinkageReading)
        /// 연결하지 않는다 — 저장소는 CloudKit 없이 연다.
        case hold(LegacySeparationHold, LegacyRowLinkageReading)

        public var hold: LegacySeparationHold? {
            if case .hold(let hold, _) = self { return hold }
            return nil
        }
    }

    public var reader: LegacyRowLinkageReader
    public var records: LegacySeparationRecordStore
    private let fileManager: FileManager

    public init(area: PreservationArea, reader: LegacyRowLinkageReader = LegacyRowLinkageReader(), fileManager: FileManager = .default) {
        self.reader = reader
        self.records = LegacySeparationRecordStore(area: area, fileManager: fileManager)
        self.fileManager = fileManager
    }

    /// 저장소(이미 현재 스키마로 옮겨진 것)를 판정하고, 대응 없는 행이 있으면 보존한 뒤 결정을 돌려준다.
    public func decide(storeURL: URL) -> Decision {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("separation-gate-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let copy: URL
        do {
            copy = try LegacyRowLinkageReader.copyStoreFiles(from: storeURL, into: scratch, fileManager: fileManager)
        } catch {
            let reading = LegacyRowLinkageReading(
                verdict: .unknown(.cannotOpen("사본을 뜨지 못했다: \(error)")), readerVersion: LegacyRowLinkageReader.version, rows: [:],
                needsUploadCount: 0, orphanCorrespondenceCount: 0, hasAccountIdentityKeys: false, metadataKeyCount: 0, storeModel: "-"
            )
            return .hold(LegacySeparationHold(reason: .linkageUnknown(.cannotOpen("사본을 뜨지 못했다: \(error)"))), reading)
        }

        let reading = reader.judge(copyAt: copy)
        switch reading.verdict {
        case .allLinked:
            return .connect(reading)
        case .unknown(let reason):
            return .hold(LegacySeparationHold(reason: .linkageUnknown(reason), readerVersion: reading.readerVersion), reading)
        case .hasVerifiedUnlinked(let targets):
            do {
                let job = try records.preserve(targets: targets, readingFrom: copy, externalDataBeside: storeURL, readerVersion: reading.readerVersion)
                let hold = LegacySeparationHold(reason: .unlinkedRowsAwaitSeparation(count: targets.count), readerVersion: reading.readerVersion, jobID: job.jobID)
                return .hold(hold, reading)
            } catch {
                return .hold(LegacySeparationHold(reason: .preservationFailed("\(error)"), readerVersion: reading.readerVersion), reading)
            }
        }
    }
}
