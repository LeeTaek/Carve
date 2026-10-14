//
//  BackupArchive.swift
//  Domain
//
//  필사 백업 파일의 컨테이너 — Apple Encrypted Archive(scrypt 암호 프로필 · LZFSE) 안의 Apple Archive 를 스트리밍으로 쓰고 푼다.
//  암호 기반 키 유도 · 암호화 · 무결성 · 압축은 AppleArchive 가 한다. 여기서는 항목 이름과 바이트만 다룬다(설계 docs/backup-import-design.md §2-1 · §2-8) —
//  manifest · items 의 뜻과 BackupLimits 는 형식(BackupPayload)의 몫이라 이 타입은 모른다.
//

import AppleArchive
import Foundation
import System

/// 백업 파일 쓰기 · 풀기. 둘 다 동기 · 스트리밍(1 MiB 조각)이다 — 부르는 쪽이 백그라운드 작업에서 부른다.
/// 작업이 취소되면 조각 사이에서 `CancellationError` 로 멈추고 만들던 것을 지운다. 암호는 어디에도 남기지 않는다(로그 · 오류 · 파일).
public enum BackupArchive {

    /// 바깥 컨테이너 프로필 — 암호(scrypt) · AES-CTR · HMAC, 서명 없음(iOS 15+)
    static var profile: ArchiveEncryptionContext.Profile { .hkdf_sha256_aesctr_hmac__scrypt__none }
    /// 한 번에 읽고 쓰는 조각 크기
    static let chunkBytes = 1 << 20

    /// 준비된 폴더를 암호화한 백업 파일 하나로 쓴다.
    /// - 입력: `stagedDirectory` — 허용 이름(manifest.json · items.json · blobs/<hex>)만 든 평문 폴더,
    ///   `destination` — 만들 파일(있으면 원자적으로 바꾼다. 그 폴더는 있어야 한다), `password` — 사용자 암호
    /// - 출력: 없음. 실패하면 `BackupArchiveError`(허용 밖 항목 · 공간 부족 · 입출력) 또는 `CancellationError`
    /// - 부작용: `destination` 과 같은 폴더에 임시 이름으로 다 쓴 뒤 옮긴다. 실패 · 취소면 임시 파일을 지우고 `destination` 은 건드리지 않는다
    public static func write(stagedDirectory: URL, to destination: URL, password: String) throws {
        try write(stagedDirectory: stagedDirectory, to: destination, password: password, availableCapacity: BackupDiskSpace.availableCapacity(at:))
    }

    /// `write(stagedDirectory:to:password:)` 의 본체 — 시험이 남은 공간 읽기를 바꾼다.
    static func write(stagedDirectory: URL, to destination: URL, password: String, availableCapacity: (URL) -> Int64?) throws {
        let entries = try BackupArchiveStagedEntry.list(in: stagedDirectory)
        let folder = destination.deletingLastPathComponent()
        let needed = estimatedFileBytes(payloadBytes: entries.reduce(0) { $0 + $1.size })
        if let available = availableCapacity(folder), available < needed {
            throw BackupArchiveError.insufficientSpace
        }
        let temporary = folder.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).partial")
        do {
            try encrypt(entries, to: temporary, password: password)
            try moveAtomically(temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw failure(error)
        }
    }

    /// 쓸 파일 크기의 넉넉한 어림 — 압축이 안 되는 바이트에 컨테이너 덧붙임(조각 무결성 · 채움)과 여유 1 MiB 를 더한다.
    static func estimatedFileBytes(payloadBytes: Int) -> Int64 {
        let payload = Int64(payloadBytes)
        return payload + payload / 16 + Int64(chunkBytes)
    }

    /// 항목을 차례로 Apple Archive 로 묶어 암호화해 새 파일 `file` 에 쓴다. 이미 있는 파일 · 링크에는 쓰지 않는다.
    /// - 부작용: 파일 생성 · 쓰기
    private static func encrypt(_ entries: [BackupArchiveStagedEntry], to file: URL, password: String) throws {
        let descriptor = try FileDescriptor.open(
            FilePath(file.path),
            .readWrite,
            options: [.create, .exclusiveCreate, .noFollow],
            permissions: .ownerReadWrite
        )
        do {
            try encrypt(entries, into: descriptor, password: password)
        } catch {
            try? descriptor.close()
            throw error
        }
        try descriptor.close()
    }

    /// 열린 파일에 암호화해 쓴다 — 시험이 쓰기에 실패하는 파일을 넣는다.
    /// - 부작용: 파일 쓰기. 파일 쓰기 실패는 싱크가 모아 두었다가 스트림을 다 닫은 뒤 첫 errno 로 던진다
    static func encrypt(_ entries: [BackupArchiveStagedEntry], into descriptor: FileDescriptor, password: String) throws {
        let context = ArchiveEncryptionContext(profile: profile, compressionAlgorithm: .lzfse)
        do {
            try context.setPassword(BackupArchivePassword.encoded(password))
        } catch {
            throw BackupArchiveError.ioFailed
        }
        let sink = BackupArchiveFileSink(descriptor: descriptor)
        try encode(entries, into: sink, context: context)
        if let failure = sink.failure {
            throw failure
        }
    }

    /// 인코더 → 암호화 스트림 → 싱크로 항목을 흘려보낸다.
    /// AppleArchive 스트림은 끝까지 다 쓴 경우에만 닫는다 — 닫기가 마지막 조각 · 무결성 정보를 쓴다. 중간에 실패 · 취소하면 닫지 않고
    /// 해제에 맡긴다(iOS 17 래퍼는 실패한 close() 뒤 해제 때 다시 닫아 죽는다 — `BackupArchiveFileSink` 참고). 해제 순서는 안쪽부터다.
    private static func encode(_ entries: [BackupArchiveStagedEntry], into sink: BackupArchiveFileSink, context: ArchiveEncryptionContext) throws {
        guard let output = ArchiveByteStream.customStream(instance: sink) else {
            throw BackupArchiveError.ioFailed
        }
        try withExtendedLifetime(output) {
            guard let encrypted = ArchiveByteStream.encryptionStream(writingTo: output, encryptionContext: context) else {
                throw BackupArchiveError.ioFailed
            }
            try withExtendedLifetime(encrypted) {
                guard let encoder = ArchiveStream.encodeStream(writingTo: encrypted) else {
                    throw BackupArchiveError.ioFailed
                }
                for entry in entries {
                    // 파일 쓰기가 이미 실패했으면 남은 항목을 암호화하지 않는다.
                    if let failure = sink.failure { throw failure }
                    try entry.write(to: encoder)
                }
                try encoder.close()
                try encrypted.close()
            }
            try output.close()
        }
    }

    /// 다 쓴 임시 파일을 `destination` 으로 옮긴다 — 같은 폴더 안 rename 이라 원자적이고, 있던 파일은 바뀐다.
    private static func moveAtomically(_ temporary: URL, to destination: URL) throws {
        guard rename(temporary.path, destination.path) == 0 else {
            throw BackupArchiveError.ioFailed
        }
    }

    /// 쓰기 · 풀기 실패를 알릴 오류로 바꾼다 — 공간 부족(ENOSPC)은 insufficientSpace, 그 밖의 입출력은 ioFailed. 취소와 이미 정한 오류는 그대로.
    static func failure(_ error: Error) -> Error {
        switch error {
        case is CancellationError, is BackupArchiveError:
            return error
        case let code as Errno where code == .noSpace:
            return BackupArchiveError.insufficientSpace
        default:
            return BackupArchiveError.ioFailed
        }
    }
}

/// 준비 폴더 안의 항목 하나 — 쓰기 전에 이름 · 종류 · 크기를 확인해 둔다.
struct BackupArchiveStagedEntry {
    /// 아카이브 안 항목
    let entry: BackupArchiveEntry
    /// 준비 폴더 안 위치
    let url: URL
    /// 바이트 수(폴더는 0)
    let size: Int

    /// 준비 폴더를 훑어 쓰기 순서(manifest.json → items.json → blobs → blobs/* 이름순)로 돌려준다.
    /// - 출력: 확인한 항목 목록. 허용 밖 이름 · 링크 · 종류가 맞지 않는 항목이 있으면 `entryRejected`, 폴더를 읽지 못하면 `ioFailed`
    /// - 부작용: 없음(읽기만)
    static func list(in directory: URL) throws -> [BackupArchiveStagedEntry] {
        var result: [BackupArchiveStagedEntry] = []
        for name in try names(in: directory) {
            guard let entry = BackupArchiveEntry(path: name) else {
                throw BackupArchiveError.rejected(name)
            }
            let url = directory.appendingPathComponent(name, isDirectory: entry.isDirectory)
            result.append(try checked(entry, at: url))
            guard entry.isDirectory else { continue }
            for blobName in try names(in: url) {
                let path = BackupArchiveEntry.blobDirectoryPath + "/" + blobName
                guard let blob = BackupArchiveEntry(path: path), !blob.isDirectory else {
                    throw BackupArchiveError.rejected(path)
                }
                result.append(try checked(blob, at: url.appendingPathComponent(blobName, isDirectory: false)))
            }
        }
        return result.sorted { $0.entry.writeOrder < $1.entry.writeOrder }
    }

    /// 폴더 안 이름 목록(숨김 파일 포함 — 허용 밖이면 거부된다).
    private static func names(in directory: URL) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw BackupArchiveError.ioFailed
        }
    }

    /// 항목의 실제 종류를 링크를 따라가지 않고 확인한다 — 폴더 항목은 폴더, 파일 항목은 일반 파일이어야 한다.
    private static func checked(_ entry: BackupArchiveEntry, at url: URL) throws -> BackupArchiveStagedEntry {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw BackupArchiveError.ioFailed
        }
        guard values.isSymbolicLink != true else {
            throw BackupArchiveError.rejected(entry.path)
        }
        if entry.isDirectory {
            guard values.isDirectory == true else { throw BackupArchiveError.rejected(entry.path) }
            return BackupArchiveStagedEntry(entry: entry, url: url, size: 0)
        }
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw BackupArchiveError.rejected(entry.path)
        }
        return BackupArchiveStagedEntry(entry: entry, url: url, size: size)
    }

    /// 헤더(TYP · PAT · DAT)와 바이트를 인코더에 쓴다 — 파일은 조각으로 읽어 흘려보낸다.
    /// - 부작용: 파일 읽기. 확인한 뒤 크기가 바뀌었으면 `ioFailed`
    func write(to encoder: ArchiveStream) throws {
        try Task.checkCancellation()
        let header = ArchiveHeader()
        let type: ArchiveHeader.EntryType = entry.isDirectory ? .directory : .regularFile
        header.append(.uint(key: BackupArchiveField.type, value: UInt64(type.rawValue)))
        header.append(.string(key: BackupArchiveField.path, value: entry.path))
        guard !entry.isDirectory else {
            try encoder.writeHeader(header)
            return
        }
        header.append(.blob(key: BackupArchiveField.data, size: UInt64(size)))
        try encoder.writeHeader(header)
        let descriptor = try FileDescriptor.open(FilePath(url.path), .readOnly, options: [.noFollow])
        try descriptor.closeAfter {
            var buffer = [UInt8](repeating: 0, count: min(BackupArchive.chunkBytes, max(size, 1)))
            var remaining = size
            while remaining > 0 {
                try Task.checkCancellation()
                let want = min(buffer.count, remaining)
                let readLength = try buffer.withUnsafeMutableBytes { raw in
                    try descriptor.read(into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<want]))
                }
                guard readLength > 0 else { throw BackupArchiveError.ioFailed }
                try buffer.withUnsafeBytes { raw in
                    try encoder.writeBlob(key: BackupArchiveField.data, from: UnsafeRawBufferPointer(rebasing: raw[0..<readLength]))
                }
                remaining -= readLength
            }
            let extra = try buffer.withUnsafeMutableBytes { raw in
                try descriptor.read(into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<1]))
            }
            guard extra == 0 else { throw BackupArchiveError.ioFailed }
        }
    }
}
