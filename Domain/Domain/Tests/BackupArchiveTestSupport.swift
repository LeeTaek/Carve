//
//  BackupArchiveTestSupport.swift
//  DomainTest
//
//  백업 컨테이너 시험의 공용 도구 — 시험마다 따로인 임시 폴더, 고정 씨앗 바이트, 허용 밖 항목을 일부러 넣은 백업 파일.
//

import AppleArchive
import CryptoKit
import Foundation
import System

@testable import Domain

/// 시험 하나가 쓰는 임시 폴더 — 끝나면 통째로 지운다. 실제 `BackupWork` 는 쓰지 않는다(병렬 시험끼리 간섭하지 않게).
struct BackupArchiveSandbox {
    /// 이 시험의 루트
    let root: URL
    /// 준비 폴더(평문)
    var staged: URL { root.appendingPathComponent("staged", isDirectory: true) }
    /// 백업 파일을 둘 폴더
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }
    /// 풀 곳(작업 폴더 자리)
    var work: URL { root.appendingPathComponent("work", isDirectory: true) }
    /// 기본 백업 파일 경로
    var archive: URL { output.appendingPathComponent("backup.carvebackup") }

    /// 새 임시 폴더(staged · out · work)를 만들어 `body` 를 돌리고 지운다.
    static func run(_ body: (BackupArchiveSandbox) throws -> Void) throws {
        let sandbox = try make()
        defer { sandbox.remove() }
        try body(sandbox)
    }

    /// 새 임시 폴더를 만든다 — async 시험은 끝에 `remove()` 를 부른다.
    static func make() throws -> BackupArchiveSandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-archive-\(UUID().uuidString)", isDirectory: true)
        let sandbox = BackupArchiveSandbox(root: root)
        for directory in [sandbox.staged, sandbox.output, sandbox.work] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return sandbox
    }

    /// 임시 폴더를 지운다.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// 준비 폴더에 파일을 쓴다(상대 경로 — 중간 폴더는 만든다).
    func stage(_ relativePath: String, _ data: Data) throws {
        let url = staged.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// 허용 이름만 든 준비 폴더를 만든다 — manifest · items · 주어진 blob 들(이름은 SHA-256).
    func stageBackup(blobs: [Data]) throws {
        try stage(BackupArchiveEntry.manifestPath, BackupArchiveFixture.manifest)
        try stage(BackupArchiveEntry.itemsPath, BackupArchiveFixture.items)
        try FileManager.default.createDirectory(at: staged.appendingPathComponent("blobs", isDirectory: true), withIntermediateDirectories: true)
        for blob in blobs {
            try stage("blobs/\(BackupArchiveFixture.blobName(blob))", blob)
        }
    }

    /// 폴더 안 파일 전부(상대 경로 → 바이트). 폴더는 담지 않는다.
    func files(in directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(path)
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            result[path] = try Data(contentsOf: url)
        }
        return result
    }

    /// 폴더 안 모든 항목의 상대 경로(정렬)
    func listing(of directory: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }
}

/// 시험 바이트와 허용 밖 백업 파일 만들기.
enum BackupArchiveFixture {
    /// 화면 최소 길이(8자) 암호 — SDK 가 그대로는 받지 않는 길이다.
    static let password = "abcd1234"
    /// manifest.json 자리의 고정 바이트(형식 검사는 이 시험의 몫이 아니다)
    static let manifest = Data(#"{"formatVersion":1}"#.utf8)
    /// items.json 자리의 고정 바이트
    static let items = Data("[]".utf8)

    /// 고정 씨앗으로 만든 섞인 바이트(xorshift) — 압축이 거의 안 되어 큰 blob 시험이 실제로 여러 조각을 지난다.
    static func bytes(count: Int, seed: UInt64) -> Data {
        var state = seed | 1
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            for index in raw.indices {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                raw[index] = UInt8(truncatingIfNeeded: state)
            }
        }
        return data
    }

    /// blob 이름 — 바이트의 소문자 SHA-256 hex 64자
    static func blobName(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 허용 밖 항목을 일부러 넣을 수 있는 아카이브 항목
    struct RawEntry {
        /// PAT 원문
        var path: String
        /// TYP
        var type: ArchiveHeader.EntryType = .regularFile
        /// DAT 바이트(nil 이면 DAT 필드 없음)
        var data: Data?
        /// LNK(링크 대상)
        var linkTarget: String?
        /// DAT 뒤에 붙이는 다른 바이트 필드(XAT)
        var extraBlob: Data?
    }

    /// 같은 컨테이너(scrypt 프로필 · LZFSE · 같은 암호 표기)로 항목을 마음대로 담은 백업 파일을 쓴다.
    static func writeRaw(_ entries: [RawEntry], to url: URL, password: String = password) throws {
        let context = ArchiveEncryptionContext(profile: BackupArchive.profile, compressionAlgorithm: .lzfse)
        try context.setPassword(BackupArchivePassword.encoded(password))
        try ArchiveByteStream.withFileStream(
            path: FilePath(url.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: .ownerReadWrite
        ) { file in
            guard let encrypted = ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context) else {
                throw BackupArchiveError.ioFailed
            }
            try ArchiveStream.withEncodeStream(writingTo: encrypted) { encoder in
                for entry in entries {
                    try write(entry, to: encoder)
                }
            }
            try encrypted.close()
        }
    }

    private static func write(_ entry: RawEntry, to encoder: ArchiveStream) throws {
        let header = ArchiveHeader()
        header.append(.uint(key: BackupArchiveField.type, value: UInt64(entry.type.rawValue)))
        header.append(.string(key: BackupArchiveField.path, value: entry.path))
        if let linkTarget = entry.linkTarget {
            header.append(.string(key: ArchiveHeader.FieldKey("LNK"), value: linkTarget))
        }
        if let data = entry.data {
            header.append(.blob(key: BackupArchiveField.data, size: UInt64(data.count)))
        }
        if let extra = entry.extraBlob {
            header.append(.blob(key: ArchiveHeader.FieldKey("XAT"), size: UInt64(extra.count)))
        }
        try encoder.writeHeader(header)
        if let data = entry.data, !data.isEmpty {
            try data.withUnsafeBytes { try encoder.writeBlob(key: BackupArchiveField.data, from: $0) }
        }
        if let extra = entry.extraBlob, !extra.isEmpty {
            try extra.withUnsafeBytes { try encoder.writeBlob(key: ArchiveHeader.FieldKey("XAT"), from: $0) }
        }
    }
}
