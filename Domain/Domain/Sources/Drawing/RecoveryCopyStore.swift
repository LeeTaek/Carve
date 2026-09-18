//
//  RecoveryCopyStore.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 복구 사본이 지키는 것 (정책 §12-6 C11).
public enum RecoveryCopyKind: String, Codable, Sendable {
    case version
    case favorite
}

/// 설정 화면에서 나눠 보여야 하는 두 종류.
public enum RecoveryCopyClassification: String, Codable, Sendable {
    /// 확정할 때 함께 남긴 정상 보관본.
    case preserved
    /// 삭제 충돌로 무효가 돼 격리된 사본.
    case quarantined
}

/// 복구 사본 한 건. 내용 자체는 지문을 키로 공유하는 blob 에 있다.
public struct RecoveryCopyEntry: Codable, Equatable, Sendable {
    public var entryID: String
    public var kind: RecoveryCopyKind
    public var classification: RecoveryCopyClassification
    /// 이 사본이 속한 계정 범위. 다른 계정 화면에 섞지 않는다.
    public var accountScope: String
    public var verseKey: String
    public var contentFingerprint: String
    public var drawingVersion: Int?
    /// 원본 레코드와 같은 `K(x)`.
    public var knownEpochs: Set<String>
    public var createdAt: Date
    public var deviceID: String

    public init(
        entryID: String = UUID().uuidString,
        kind: RecoveryCopyKind,
        classification: RecoveryCopyClassification = .preserved,
        accountScope: String,
        verseKey: String,
        contentFingerprint: String,
        drawingVersion: Int? = nil,
        knownEpochs: Set<String> = [],
        createdAt: Date = Date(),
        deviceID: String
    ) {
        self.entryID = entryID
        self.kind = kind
        self.classification = classification
        self.accountScope = accountScope
        self.verseKey = verseKey
        self.contentFingerprint = contentFingerprint
        self.drawingVersion = drawingVersion
        self.knownEpochs = knownEpochs
        self.createdAt = createdAt
        self.deviceID = deviceID
    }
}

/// 설정 화면에 보여 줄 사용량. 보관본과 격리본을 나눠 센다.
public struct RecoveryCopyUsage: Equatable, Sendable {
    public var preservedEntries: Int
    public var quarantinedEntries: Int
    /// 공유된 blob 의 실제 바이트 합. 같은 내용을 여러 사본이 참조해도 한 번만 센다.
    public var blobBytes: Int

    public init(preservedEntries: Int = 0, quarantinedEntries: Int = 0, blobBytes: Int = 0) {
        self.preservedEntries = preservedEntries
        self.quarantinedEntries = quarantinedEntries
        self.blobBytes = blobBytes
    }
}

/// 확정 순서(§12-6 C2 · C11)가 쓰는 최소 인터페이스. 저장에 실패하면 던진다 — **확정하지 않기 위해서다.**
public protocol RecoveryCopyWriting {
    /// 사본을 내구성 있게 저장한다. 돌아오면 저장이 끝나 있어야 한다.
    func save(_ entry: RecoveryCopyEntry, blob: Data) throws
}

public enum RecoveryCopyStoreError: Error, Equatable {
    /// 항목이 가리키는 blob 이 없다. 항목보다 blob 을 먼저 쓰므로 정상 경로에서는 나오지 않는다.
    case blobMissing(String)
}

/// 비동기화 영역에 두는 파일 기반 복구 사본 저장소 (정책 §12-6 C11).
///
/// 규칙 세 가지를 코드로 고정한다.
/// 1. **blob 을 먼저, 항목을 나중에** 쓴다 — 중간에 끊겨도 내용 없는 항목이 남지 않는다.
/// 2. **저장은 아무것도 지우지 않는다.** 공간이 부족하면 실패로 두고, 기존 사본을 치워 자리를 만들지 않는다.
/// 3. 삭제는 명시적인 `remove` 뿐이고, blob 은 **참조가 모두 사라졌을 때만** 지운다.
public struct FileRecoveryCopyStore: RecoveryCopyWriting {
    private let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func save(_ entry: RecoveryCopyEntry, blob: Data) throws {
        try fileManager.createDirectory(at: blobDirectory(entry.accountScope), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: entryDirectory(entry.accountScope), withIntermediateDirectories: true)

        let blobURL = blobURL(entry.accountScope, fingerprint: entry.contentFingerprint)
        if !fileManager.fileExists(atPath: blobURL.path) {
            try blob.write(to: blobURL, options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entry).write(to: entryURL(entry.accountScope, entryID: entry.entryID), options: .atomic)
    }

    /// 한 계정 범위의 사본 목록. 다른 계정 범위는 읽지 않는다.
    public func entries(accountScope: String) throws -> [RecoveryCopyEntry] {
        let directory = entryDirectory(accountScope)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try urls
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(RecoveryCopyEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 사본의 내용. 항목이 있는데 내용이 없으면 던진다 — 조용히 빈 값으로 되살리지 않는다.
    public func blob(for entry: RecoveryCopyEntry) throws -> Data {
        let url = blobURL(entry.accountScope, fingerprint: entry.contentFingerprint)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RecoveryCopyStoreError.blobMissing(entry.contentFingerprint)
        }
        return try Data(contentsOf: url)
    }

    /// 사용자가 지우거나 이 기기의 전체 삭제 작업이 정리할 때만 부른다.
    /// 남은 항목이 같은 내용을 참조하면 blob 은 남긴다(§12-6 C11 단계 ④).
    public func remove(entryID: String, accountScope: String) throws {
        let remaining = try entries(accountScope: accountScope)
        guard let target = remaining.first(where: { $0.entryID == entryID }) else { return }
        try fileManager.removeItem(at: entryURL(accountScope, entryID: entryID))

        let stillReferenced = remaining
            .filter { $0.entryID != entryID }
            .map(\.contentFingerprint)
        let removable = EraseJobRule.removableBlobs(
            all: [target.contentFingerprint],
            referencedByKept: Set(stillReferenced)
        )
        for fingerprint in removable {
            let url = blobURL(accountScope, fingerprint: fingerprint)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    public func usage(accountScope: String) throws -> RecoveryCopyUsage {
        let entries = try entries(accountScope: accountScope)
        var usage = RecoveryCopyUsage(
            preservedEntries: entries.filter { $0.classification == .preserved }.count,
            quarantinedEntries: entries.filter { $0.classification == .quarantined }.count
        )
        for fingerprint in Set(entries.map(\.contentFingerprint)) {
            let url = blobURL(accountScope, fingerprint: fingerprint)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            usage.blobBytes += (attributes?[.size] as? Int) ?? 0
        }
        return usage
    }

    private func scopeDirectory(_ accountScope: String) -> URL {
        root.appendingPathComponent(accountScope, isDirectory: true)
    }

    private func blobDirectory(_ accountScope: String) -> URL {
        scopeDirectory(accountScope).appendingPathComponent("blobs", isDirectory: true)
    }

    private func entryDirectory(_ accountScope: String) -> URL {
        scopeDirectory(accountScope).appendingPathComponent("entries", isDirectory: true)
    }

    private func blobURL(_ accountScope: String, fingerprint: String) -> URL {
        blobDirectory(accountScope).appendingPathComponent(fingerprint)
    }

    private func entryURL(_ accountScope: String, entryID: String) -> URL {
        entryDirectory(accountScope).appendingPathComponent("\(entryID).json")
    }
}
