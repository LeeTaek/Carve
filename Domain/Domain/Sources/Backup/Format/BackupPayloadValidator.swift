//
//  BackupPayloadValidator.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 풀린 백업을 **저장소를 바꾸기 전에** 검사한다 (설계 §4-2). 어긋나면 파일 전체를 거부한다.
///
/// 색인 파일(`manifest.json` · `items.json`)의 크기 상한(`maxIndexBytes`)은 디코딩 전에 `BackupPayload.load` 가 이 타입의 `readIndexFile` 로 본다.
/// 순서는 싼 것부터다 — 형식 버전 → 항목 수 → manifest blob 목록(이름 · 해시 · 중복 · 크기 상한) → `counts` → 항목(중복 id · 같은 id 다른 지문 ·
/// manifest 에 없는 blob 참조) → 참조되지 않는 blob → blob 실제 크기 · SHA-256 → blob 바이트로 다시 계산한 내용 지문.
/// 파일 크기를 묻는 API(필수 사유 API)를 쓰지 않고, 읽은 바이트 수로 크기를 본다 — 상한 + 1 바이트까지만 읽는다.
public enum BackupPayloadValidator {
    /// 검사한다.
    /// - Parameters:
    ///   - manifest: 디코딩한 manifest.
    ///   - items: 디코딩한 항목 목록.
    ///   - blobDirectory: `blobs/` 폴더.
    ///   - limits: 상한.
    /// - Throws: 첫 번째로 어긋난 것의 `BackupFormatError`. 부작용 없음(파일을 읽기만 한다).
    public static func validate(manifest: BackupManifest, items: [BackupItem], blobDirectory: URL, limits: BackupLimits) throws {
        guard manifest.formatVersion == BackupFormat.formatVersion else {
            throw BackupFormatError.unsupportedFormat(formatVersion: manifest.formatVersion)
        }
        guard items.count <= limits.maxItems else { throw BackupFormatError.limitExceeded(.items) }

        let blobNames = try checkBlobEntries(manifest.blobs, limits: limits)
        let rows = items.filter { $0.kind == .row }.count
        let drafts = items.filter { $0.kind == .draft }.count
        guard manifest.counts == BackupCounts(rows: rows, drafts: drafts, blobs: manifest.blobs.count) else {
            throw BackupFormatError.countsMismatch
        }

        let referenced = try checkItems(items, blobNames: blobNames)
        if let unreferenced = manifest.blobs.first(where: { !referenced.contains($0.name) }) {
            throw BackupFormatError.unreferencedBlob(name: unreferenced.name)
        }

        for entry in manifest.blobs {
            try checkBlobBytes(entry, blobDirectory: blobDirectory, limits: limits)
        }
        try checkFingerprints(items, blobDirectory: blobDirectory, limits: limits)
    }

    /// manifest blob 목록 — 이름 형식 · `name == sha256` · 크기(음수 · 하나 · 합계 상한) · 중복.
    /// - Returns: blob 이름 집합.
    private static func checkBlobEntries(_ entries: [BackupBlobEntry], limits: BackupLimits) throws -> Set<String> {
        var names: Set<String> = []
        var total = 0
        for entry in entries {
            guard BackupFormat.isBlobName(entry.name), entry.sha256 == entry.name, entry.size >= 0 else {
                throw BackupFormatError.invalidBlobEntry(name: entry.name)
            }
            guard names.insert(entry.name).inserted else { throw BackupFormatError.duplicateBlob(name: entry.name) }
            guard entry.size <= limits.maxBlobBytes else { throw BackupFormatError.limitExceeded(.blobBytes) }
            let (sum, overflow) = total.addingReportingOverflow(entry.size)
            guard !overflow, sum <= limits.maxTotalBytes else { throw BackupFormatError.limitExceeded(.totalBytes) }
            total = sum
        }
        return names
    }

    /// 항목 — 중복 id(같은 지문이면 `duplicateItemID`, 다르면 무결성 오류) · manifest 에 없는 blob 참조.
    /// - Returns: 항목이 가리키는 blob 이름 집합.
    private static func checkItems(_ items: [BackupItem], blobNames: Set<String>) throws -> Set<String> {
        var fingerprintsByID: [String: String?] = [:]
        var referenced: Set<String> = []
        for item in items {
            if let seen = fingerprintsByID[item.id] {
                guard seen == item.fingerprint else {
                    throw BackupFormatError.integrity(itemID: item.id, .conflictingFingerprint)
                }
                throw BackupFormatError.duplicateItemID(item.id)
            }
            fingerprintsByID[item.id] = .some(item.fingerprint)
            for name in [item.inkBlob, item.metadataBlob].compactMap({ $0 }) {
                guard blobNames.contains(name) else { throw BackupFormatError.missingBlob(name: name) }
                referenced.insert(name)
            }
        }
        return referenced
    }

    /// blob 파일 하나의 실제 크기 · SHA-256 이 manifest 와 같은가.
    private static func checkBlobBytes(_ entry: BackupBlobEntry, blobDirectory: URL, limits: BackupLimits) throws {
        let bytes = try readBlob(named: entry.name, blobDirectory: blobDirectory, limit: limits.maxBlobBytes)
        guard bytes.count <= limits.maxBlobBytes else { throw BackupFormatError.limitExceeded(.blobBytes) }
        guard bytes.count == entry.size else { throw BackupFormatError.blobSizeMismatch(name: entry.name) }
        guard BackupFormat.sha256Hex(bytes) == entry.sha256 else { throw BackupFormatError.blobHashMismatch(name: entry.name) }
    }

    /// 항목마다 blob 바이트로 내용 지문을 다시 계산해 항목 `fingerprint` 와 견준다 — 잉크가 없으면 nil 이어야 한다.
    ///
    /// 같은 (잉크 · 좌표 형식 · 메타데이터) 조합은 한 번만 계산한다.
    private static func checkFingerprints(_ items: [BackupItem], blobDirectory: URL, limits: BackupLimits) throws {
        var cache: [FingerprintInput: String] = [:]
        for item in items {
            let expected: String?
            if let inkBlob = item.inkBlob {
                let input = FingerprintInput(inkBlob: inkBlob, drawingVersion: item.drawingVersion, metadataBlob: item.metadataBlob)
                if let cached = cache[input] {
                    expected = cached
                } else {
                    let ink = try readBlob(named: inkBlob, blobDirectory: blobDirectory, limit: limits.maxBlobBytes)
                    let metadata = try item.metadataBlob.map {
                        try readBlob(named: $0, blobDirectory: blobDirectory, limit: limits.maxBlobBytes)
                    }
                    let made = VerseContentFingerprint.make(lineData: ink, drawingVersion: item.drawingVersion, layoutMetadataBlob: metadata)
                    cache[input] = made
                    expected = made
                }
            } else {
                expected = nil
            }
            guard expected == item.fingerprint else {
                throw BackupFormatError.integrity(itemID: item.id, .fingerprintMismatch)
            }
        }
    }

    /// 색인 파일(`manifest.json` · `items.json`) 하나를 `maxIndexBytes + 1` 바이트까지만 읽는다 — `BackupPayload.load` 가 디코딩 전에 부른다.
    /// - Parameters:
    ///   - fileName: 루트 아래 파일 이름.
    ///   - rootDirectory: 풀린 루트.
    ///   - limits: 상한(`maxIndexBytes`).
    /// - Returns: 파일 바이트.
    /// - Throws: 파일이 없거나 읽지 못하면 `malformed(fileName:)`, 상한을 넘으면 `limitExceeded(.indexBytes)`. 부작용 없음.
    static func readIndexFile(named fileName: String, in rootDirectory: URL, limits: BackupLimits) throws -> Data {
        let bytes: Data
        do {
            bytes = try readBounded(rootDirectory.appendingPathComponent(fileName, isDirectory: false), limit: limits.maxIndexBytes)
        } catch {
            throw BackupFormatError.malformed(fileName: fileName)
        }
        guard bytes.count <= limits.maxIndexBytes else { throw BackupFormatError.limitExceeded(.indexBytes) }
        return bytes
    }

    /// blob 파일을 `limit + 1` 바이트까지만 읽는다.
    /// - Throws: 파일이 없거나 읽지 못하면 `missingBlob`.
    static func readBlob(named name: String, blobDirectory: URL, limit: Int) throws -> Data {
        do {
            return try readBounded(BackupPayload.blobURL(named: name, in: blobDirectory), limit: limit)
        } catch {
            throw BackupFormatError.missingBlob(name: name)
        }
    }

    /// 파일을 `limit + 1` 바이트까지만 읽는다 — 상한을 넘는 파일을 메모리에 다 올리지 않고 넘었음을 안다(크기를 묻는 API 를 쓰지 않는다).
    private static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let count = limit == Int.max ? limit : limit + 1
        return try handle.read(upToCount: count) ?? Data()
    }

    /// 지문 계산 입력의 캐시 키.
    private struct FingerprintInput: Hashable {
        let inkBlob: String
        let drawingVersion: Int?
        let metadataBlob: String?
    }
}
