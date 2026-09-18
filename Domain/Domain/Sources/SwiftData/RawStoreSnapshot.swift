//
//  RawStoreSnapshot.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import CryptoKit
import Foundation
import SQLite3

/// 비동기화 보존 영역의 위치 (정책 §12-6 C3). 저장소 파일 이름마다 따로 둔다 — Debug(dev) 와 운영 저장소가 섞이지 않는다.
public struct PreservationArea: Equatable, Sendable {
    public let root: URL
    public let storeFileName: String

    public init(root: URL, storeFileName: String) {
        self.root = root
        self.storeFileName = storeFileName
    }

    /// 앱이 쓰는 위치. iCloud(CloudKit) 로 동기화되지 않는 Application Support 아래다.
    public static func live(localDBPath: String) -> PreservationArea {
        PreservationArea(
            root: URL.applicationSupportDirectory.appending(path: "Preservation", directoryHint: .isDirectory),
            storeFileName: localDBPath
        )
    }

    var storeDirectory: URL { root.appendingPathComponent(storeFileName, isDirectory: true) }
    var rawSnapshotsDirectory: URL { storeDirectory.appendingPathComponent("raw", isDirectory: true) }
    /// 복구 사본 · 격리본(`FileRecoveryCopyStore`)의 위치. 보존 영역 안에 있으므로 이 기기의 전체 삭제가 함께 지운다.
    public var recoveryCopiesDirectory: URL { storeDirectory.appendingPathComponent("recovery", isDirectory: true) }
    var notNeededMarker: URL { storeDirectory.appendingPathComponent("raw-not-needed.json") }

    /// 이 저장소의 보존 영역을 모두 지운다. **사용자가 이 기기에서 전체 삭제를 요청했을 때만** 부른다(§12-6 C11 단계 ④).
    /// 2.0.0 은 보존 영역을 자동으로 정리하지 않는다.
    public func removeAll(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: storeDirectory.path) else { return }
        try fileManager.removeItem(at: storeDirectory)
    }
}

/// 원시 사본 (정책 §12-6 C3 ①).
///
/// 새 저장 모델로 저장소를 **처음 열기 전에** 저장소 파일을 그대로 떠 둔다. 그 뒤 마이그레이션 · 가져오기가 저장소를
/// 바꿔도, 이 버전이 처음 본 legacy 원본은 여기 남는다. 원본 저장소는 **읽기만** 한다.
///
/// 완료 조건은 두 가지다 — SQLite 무결성 검사 통과, 외부 저장으로 참조된 blob 파일이 모두 있고 읽힌다.
/// 하나라도 어긋나면 사본을 남기지 않고 실패를 돌려준다. 호출부는 **저장소를 열지 않고** 시작을 막는다 —
/// 보호되지 않은 채 새 모델로 열어 CloudKit 에 연결하지 않기 위해서다.
enum RawStoreSnapshot {
    /// 사본 형식 자체의 버전.
    static let formatVersion = 1

    enum Outcome: Equatable {
        /// 이번에 떴다.
        case created(URL)
        /// 이미 떠 둔 사본이 있다. 다시 뜨지 않는다 — 이미 새 모델로 연 저장소를 "원본" 으로 덮어쓰지 않기 위해서다.
        case alreadyTaken(URL)
        /// 처음 실행할 때 저장소가 없었다. 옮길 원본이 없다.
        case notNeeded
    }

    enum Failure: Error, Equatable {
        /// 복사하지 못했다(공간 부족 · 읽기 실패).
        case copyFailed(String)
        /// 복사본의 크기가 원본과 다르다.
        case sizeMismatch(String)
        /// SQLite 무결성 검사를 통과하지 못했다.
        case integrityCheckFailed(String)
        /// 외부 저장으로 참조된 blob 파일이 없거나 읽히지 않는다.
        case externalDataMissing([String])
        /// 사본 목록 · 완료 표시를 남기지 못했다.
        case recordFailed(String)
    }

    /// 사본 폴더 안의 목록. 이 파일이 있어야 완료된 사본이다.
    struct Manifest: Codable, Equatable {
        struct FileEntry: Codable, Equatable {
            var path: String
            var bytes: Int
            var sha256: String
        }

        var formatVersion: Int
        var snapshotID: String
        var storeFileName: String
        var createdAt: Date
        var files: [FileEntry]
        /// 외부 저장으로 참조된 blob 수. 모두 사본 안에 있고 읽혔다.
        var externalReferences: Int
    }

    private static let manifestName = "manifest.json"
    private static let partialSuffix = ".partial"
    /// 복사 중 원본이 바뀌었을 때 다시 뜨는 횟수와 간격. 시작 경로이므로 짧게 둔다.
    private static let maxRetriesOnChange = 3
    private static let retryDelay: TimeInterval = 0.2

    /// 필요하면 원시 사본을 뜬다. 같은 저장소에 대해 한 번만 뜬다.
    static func takeIfNeeded(
        storeURL: URL,
        area: PreservationArea,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> Result<Outcome, Failure> {
        if let existing = completedSnapshot(in: area, fileManager: fileManager) {
            return .success(.alreadyTaken(existing))
        }
        if fileManager.fileExists(atPath: area.notNeededMarker.path) {
            return .success(.notNeeded)
        }
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return record(notNeededIn: area, fileManager: fileManager, now: now)
        }

        let snapshotID = "\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let staging = area.rawSnapshotsDirectory.appendingPathComponent(snapshotID + partialSuffix, isDirectory: true)
        let final = area.rawSnapshotsDirectory.appendingPathComponent(snapshotID, isDirectory: true)
        removeAbandonedStaging(in: area, fileManager: fileManager)

        var result = stage(storeURL: storeURL, into: staging, snapshotID: snapshotID, area: area, fileManager: fileManager, now: now)
        // 복사하는 동안 원본이 바뀌었다(크기 불일치). 앞서 닫힌 연결이 WAL 을 정리하는 중일 수 있어 잠시 뒤 다시 뜬다.
        // 계속 바뀌면 누군가 쓰고 있다는 뜻이므로 실패로 둔다 — 쓰는 도중의 파일을 원본이라 부르지 않는다.
        for _ in 0..<maxRetriesOnChange {
            guard case .failure(.sizeMismatch(let path)) = result else { break }
            Log.info("원시 사본 — 복사 중 원본이 바뀌어 다시 뜬다", path)
            try? fileManager.removeItem(at: staging)
            Thread.sleep(forTimeInterval: retryDelay)
            result = stage(storeURL: storeURL, into: staging, snapshotID: snapshotID, area: area, fileManager: fileManager, now: now)
        }
        switch result {
        case .failure(let failure):
            try? fileManager.removeItem(at: staging)
            return .failure(failure)
        case .success:
            do {
                try fileManager.moveItem(at: staging, to: final)
                try? DurableFile.flush(area.rawSnapshotsDirectory)
            } catch {
                try? fileManager.removeItem(at: staging)
                return .failure(.recordFailed("\(error)"))
            }
            return .success(.created(final))
        }
    }

    // MARK: - 저장소 파일

    /// 저장소 본 파일과 함께 떠야 하는 파일들. 있는 것만 돌려준다.
    static func storeFiles(for storeURL: URL, fileManager: FileManager = .default) -> [URL] {
        let candidates = [storeURL] + ["-wal", "-shm", "-journal"].map {
            storeURL.deletingLastPathComponent().appendingPathComponent(storeURL.lastPathComponent + $0)
        }
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// 외부 저장 폴더. `Carve.sqlite` 면 `.Carve_SUPPORT` 다.
    static func supportDirectory(for storeURL: URL) -> URL {
        let base = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent().appendingPathComponent(".\(base)_SUPPORT", isDirectory: true)
    }

    // MARK: - 단계

    private static func stage(
        storeURL: URL,
        into staging: URL,
        snapshotID: String,
        area: PreservationArea,
        fileManager: FileManager,
        now: Date
    ) -> Result<Void, Failure> {
        let sources = storeFiles(for: storeURL, fileManager: fileManager)
        let support = supportDirectory(for: storeURL)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            for source in sources {
                try fileManager.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
            }
            if fileManager.fileExists(atPath: support.path) {
                try fileManager.copyItem(at: support, to: staging.appendingPathComponent(support.lastPathComponent, isDirectory: true))
            }
        } catch {
            return .failure(.copyFailed("\(error)"))
        }

        let entries: [Manifest.FileEntry]
        do {
            entries = try fileEntries(in: staging, comparingWith: storeURL.deletingLastPathComponent(), fileManager: fileManager)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.copyFailed("\(error)"))
        }

        let externalReferences: Int
        switch verify(staging: staging, storeFileName: storeURL.lastPathComponent, supportName: support.lastPathComponent, fileManager: fileManager) {
        case .failure(let failure): return .failure(failure)
        case .success(let count): externalReferences = count
        }

        let manifest = Manifest(
            formatVersion: formatVersion,
            snapshotID: snapshotID,
            storeFileName: area.storeFileName,
            createdAt: now,
            files: entries,
            externalReferences: externalReferences
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            try DurableFile.write(try encoder.encode(manifest), to: staging.appendingPathComponent(manifestName))
        } catch {
            return .failure(.recordFailed("\(error)"))
        }
        return .success(())
    }

    /// 복사한 파일마다 크기를 원본과 맞춰 보고 지문을 남긴다.
    private static func fileEntries(in staging: URL, comparingWith sourceDirectory: URL, fileManager: FileManager) throws -> [Manifest.FileEntry] {
        guard let enumerator = fileManager.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var entries: [Manifest.FileEntry] = []
        // `/var` 와 `/private/var` 처럼 같은 폴더가 다른 경로로 보일 수 있어 둘 다 풀어서 비교한다.
        let prefix = staging.resolvingSymlinksInPath().path + "/"
        for case let url as URL in enumerator {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count))
            let copied = try fileSize(url, fileManager: fileManager)
            let original = try fileSize(sourceDirectory.appendingPathComponent(relative), fileManager: fileManager)
            guard copied == original else { throw Failure.sizeMismatch(relative) }
            entries.append(Manifest.FileEntry(path: relative, bytes: copied, sha256: try sha256(of: url)))
        }
        return entries.sorted { $0.path < $1.path }
    }

    /// 사본을 검사한다. 사본 자체는 건드리지 않으려고 **검사용 복제본**을 따로 떠서 연다 — WAL 저장소는 열고 닫는 것만으로
    /// 본 파일이 바뀔 수 있다. 돌려주는 값은 외부 저장 참조 수다.
    private static func verify(staging: URL, storeFileName: String, supportName: String, fileManager: FileManager) -> Result<Int, Failure> {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("raw-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let clone = scratch.appendingPathComponent(storeFileName)
        do {
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let source = staging.appendingPathComponent(storeFileName + suffix)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: scratch.appendingPathComponent(storeFileName + suffix))
                }
            }
        } catch {
            return .failure(.copyFailed("\(error)"))
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(clone.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return .failure(.integrityCheckFailed("열지 못함"))
        }
        defer { sqlite3_close(database) }

        let integrity = textRows(database, "PRAGMA integrity_check")
        guard integrity == ["ok"] else {
            return .failure(.integrityCheckFailed(integrity.prefix(3).joined(separator: " / ")))
        }

        let externalDirectory = staging.appendingPathComponent(supportName, isDirectory: true).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        var referenced = 0
        var missing: [String] = []
        for name in externalReferenceNames(database) {
            referenced += 1
            let url = externalDirectory.appendingPathComponent(name)
            if (try? Data(contentsOf: url, options: .mappedIfSafe)) == nil {
                missing.append(name)
            }
        }
        return missing.isEmpty ? .success(referenced) : .failure(.externalDataMissing(missing.sorted()))
    }

    /// 외부 저장으로 빠진 값의 파일 이름들. Core Data 는 외부 저장 속성 칸에 `0x01` + 값(안에 둠) 또는
    /// `0x02` + 파일 이름 + `NUL`(`_EXTERNAL_DATA` 로 뺌)을 적는다.
    private static func externalReferenceNames(_ database: OpaquePointer) -> [String] {
        var names: [String] = []
        for table in textRows(database, "SELECT name FROM sqlite_master WHERE type = 'table'") {
            let columns = rows(database, "PRAGMA table_info(\"\(table)\")") { statement in
                (text(statement, 1) ?? "", (text(statement, 2) ?? "").uppercased())
            }
            for (column, type) in columns where type == "BLOB" {
                let query = "SELECT \"\(column)\" FROM \"\(table)\" WHERE substr(\"\(column)\", 1, 1) = X'02'"
                names += rows(database, query) { statement -> String? in
                    guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                    let name = data.dropFirst().prefix { $0 != 0 }
                    return String(data: Data(name), encoding: .ascii)
                }.compactMap { $0 }
            }
        }
        return names
    }

    // MARK: - 기록

    private static func completedSnapshot(in area: PreservationArea, fileManager: FileManager) -> URL? {
        guard let children = try? fileManager.contentsOfDirectory(at: area.rawSnapshotsDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return children
            .filter { !$0.lastPathComponent.hasSuffix(partialSuffix) }
            .filter { fileManager.fileExists(atPath: $0.appendingPathComponent(manifestName).path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// 지난 실행이 남긴 미완성 사본 폴더. 원본은 그대로이므로 지우고 다시 뜬다.
    private static func removeAbandonedStaging(in area: PreservationArea, fileManager: FileManager) {
        guard let children = try? fileManager.contentsOfDirectory(at: area.rawSnapshotsDirectory, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent.hasSuffix(partialSuffix) {
            try? fileManager.removeItem(at: child)
        }
    }

    private static func record(notNeededIn area: PreservationArea, fileManager: FileManager, now: Date) -> Result<Outcome, Failure> {
        do {
            try fileManager.createDirectory(at: area.storeDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try DurableFile.write(try encoder.encode(["decidedAt": now]), to: area.notNeededMarker)
            return .success(.notNeeded)
        } catch {
            return .failure(.recordFailed("\(error)"))
        }
    }

    // MARK: - 도우미

    private static func fileSize(_ url: URL, fileManager: FileManager) throws -> Int {
        (try fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func textRows(_ database: OpaquePointer, _ sql: String) -> [String] {
        rows(database, sql) { text($0, 0) }.compactMap { $0 }
    }

    private static func rows<Row>(_ database: OpaquePointer, _ sql: String, _ read: (OpaquePointer) -> Row) -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            Log.error("원시 사본 검사 — 질의를 준비하지 못했다", sql, message)
            return []
        }
        defer { sqlite3_finalize(statement) }
        var result: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(read(statement))
        }
        return result
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}
