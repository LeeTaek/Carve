//
//  BackupArchive+Read.swift
//  Domain
//
//  백업 파일 풀기 — 복호화 스트림을 풀면서 항목마다 이름 · 종류 · 크기를 검사하고, 넘으면 그 자리에서 멈춘다(설계 §2-1 · §2-8 · §4-2).
//

import AppleArchive
import Foundation
import System

extension BackupArchive {

    /// 백업 파일을 풀어 `directory` 안 새 폴더에 평문 항목을 만든다.
    /// - 입력: `source` — 백업 파일(앱 작업 영역의 사본), `password` — 사용자 암호, `directory` — 풀 곳(작업 폴더, 없으면 만든다),
    ///   `maxEntryBytes` — 항목(파일) 하나의 바이트 상한, `maxTotalBytes` — 풀린 바이트 합계의 상한,
    ///   `maxEntryCount` — 풀 파일 항목 수의 상한(manifest.json · items.json · blob 을 모두 센다. `blobs` 폴더는 세지 않는다)
    /// - 출력: 풀린 루트 폴더(`directory/Unpacked-<UUID>/`) — manifest.json · items.json · blobs/<hex> 밖의 것은 없다.
    ///   빠진 항목 · 내용의 뜻은 보지 않는다(형식 검사는 `BackupPayload` 의 몫)
    /// - 부작용: 파일 쓰기. 복호화 실패 · 허용 밖 항목 · 상한 초과 · 공간 부족 · 취소면 그 자리에서 멈추고 루트 폴더를 지운다
    public static func read(
        from source: URL,
        password: String,
        into directory: URL,
        maxEntryBytes: Int,
        maxTotalBytes: Int,
        maxEntryCount: Int = .max
    ) throws -> URL {
        try read(
            from: source,
            password: password,
            into: directory,
            maxEntryBytes: maxEntryBytes,
            maxTotalBytes: maxTotalBytes,
            maxEntryCount: maxEntryCount,
            availableCapacity: BackupDiskSpace.availableCapacity(at:)
        )
    }

    /// `read(from:password:into:maxEntryBytes:maxTotalBytes:maxEntryCount:)` 의 본체 — 시험이 남은 공간 읽기를 바꾼다.
    static func read(
        from source: URL,
        password: String,
        into directory: URL,
        maxEntryBytes: Int,
        maxTotalBytes: Int,
        maxEntryCount: Int = .max,
        availableCapacity: (URL) -> Int64?
    ) throws -> URL {
        let root = directory.appendingPathComponent("Unpacked-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw BackupArchiveError.ioFailed
        }
        do {
            var unpacker = BackupArchiveUnpacker(root: root, maxEntryBytes: maxEntryBytes, maxTotalBytes: maxTotalBytes, maxEntryCount: maxEntryCount)
            try unpack(source, password: password, with: &unpacker, availableCapacity: availableCapacity)
            return root
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw failure(error)
        }
    }

    /// 복호화 → 아카이브 해독 → 항목마다 검사 · 쓰기.
    /// AppleArchive 스트림은 닫지 않고 해제에 맡긴다(안쪽부터) — iOS 17 래퍼는 실패한 close() 뒤 해제 때 다시 닫아 죽는다(`BackupArchiveFileSink` 참고).
    /// 무결성 검사는 읽는 도중에 끝난다 — 잘림 · 변조는 모두 헤더 · 바이트를 읽다가 드러난다(17.5 · 26 에서 자리마다 확인).
    private static func unpack(
        _ source: URL,
        password: String,
        with unpacker: inout BackupArchiveUnpacker,
        availableCapacity: (URL) -> Int64?
    ) throws {
        guard let fileStream = ArchiveByteStream.fileStream(path: FilePath(source.path), mode: .readOnly, options: [], permissions: []) else {
            throw BackupArchiveError.ioFailed
        }
        try withExtendedLifetime(fileStream) {
            // 암호화 파일이 아니거나 앞머리가 손상됐으면 문맥을 읽지 못한다. 다른 프로필(키 · 서명)로 만든 파일도 받지 않는다.
            guard let context = ArchiveEncryptionContext(from: fileStream), context.profile == profile else {
                throw BackupArchiveError.wrongPasswordOrDamaged
            }
            do {
                try context.setPassword(BackupArchivePassword.encoded(password))
            } catch {
                throw BackupArchiveError.wrongPasswordOrDamaged
            }
            // 암호가 틀리거나 머리 무결성이 깨졌으면 복호화 스트림을 열지 못한다.
            guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: fileStream, encryptionContext: context) else {
                throw BackupArchiveError.wrongPasswordOrDamaged
            }
            try withExtendedLifetime(decrypted) {
                // 풀린 아카이브 크기를 알면 남은 공간을 먼저 본다 — 합계 상한보다 많이 쓰지는 않는다.
                let expected = min(Int64(context.rawSize), Int64(clamping: unpacker.maxTotalBytes))
                if expected > 0, let available = availableCapacity(unpacker.root), available < expected {
                    throw BackupArchiveError.insufficientSpace
                }
                guard let decoder = ArchiveStream.decodeStream(readingFrom: decrypted) else {
                    throw BackupArchiveError.wrongPasswordOrDamaged
                }
                while true {
                    try Task.checkCancellation()
                    let header: ArchiveHeader?
                    do {
                        header = try decoder.readHeader()
                    } catch {
                        // 복호화 무결성 실패 · 잘림, 그리고 해독기가 헤더에서 먼저 거부하는 정규형이 아닌 경로(.. · 절대 경로 · 겹친 /)가 여기로 온다.
                        throw BackupArchiveError.wrongPasswordOrDamaged
                    }
                    guard let header else { break }
                    try unpacker.extract(header, from: decoder)
                }
            }
        }
    }
}

/// 푸는 동안의 상태 — 이미 본 항목(중복 거부)과 지금까지 푼 파일 수 · 바이트.
struct BackupArchiveUnpacker {
    /// 풀 루트 폴더(이 풀기가 새로 만든 빈 폴더)
    let root: URL
    /// 항목 하나의 바이트 상한
    let maxEntryBytes: UInt64
    /// 풀린 바이트 합계의 상한
    let maxTotalBytes: UInt64
    /// 풀 파일 항목 수의 상한
    let maxEntryCount: Int
    /// 이미 푼 항목
    private(set) var seen: Set<BackupArchiveEntry> = []
    /// 지금까지 푼 파일 항목 수
    private(set) var fileCount = 0
    /// 지금까지 푼 바이트 합계
    private(set) var totalBytes: UInt64 = 0

    init(root: URL, maxEntryBytes: Int, maxTotalBytes: Int, maxEntryCount: Int) {
        self.root = root
        self.maxEntryBytes = UInt64(max(maxEntryBytes, 0))
        self.maxTotalBytes = UInt64(max(maxTotalBytes, 0))
        self.maxEntryCount = max(maxEntryCount, 0)
    }

    /// 항목 하나를 검사하고 루트 폴더 안에 만든다. 바이트를 쓰기 전에 이름 · 종류 · 필드 · 크기를 모두 본다.
    /// - 입력: 방금 읽은 헤더, 그 바이트를 이어서 읽을 해독 스트림
    /// - 부작용: 폴더 · 파일 생성. 허용 밖이면 `entryRejected`, 파일 수 · 바이트 상한을 넘으면 `tooLarge`, 바이트가 깨졌으면 `wrongPasswordOrDamaged`
    mutating func extract(_ header: ArchiveHeader, from decoder: ArchiveStream) throws {
        let path = Self.pathField(of: header) ?? ""
        guard let entry = BackupArchiveEntry(path: path), seen.insert(entry).inserted else {
            throw BackupArchiveError.rejected(path)
        }
        let dataSize = try Self.dataSize(of: header, path: path)
        if entry.isDirectory {
            guard header.entryType == .directory, dataSize == nil else { throw BackupArchiveError.rejected(path) }
            try makeDirectory(root.appendingPathComponent(entry.path, isDirectory: true))
            return
        }
        // 링크 · 장치 파일 등 일반 파일이 아닌 것은 이름이 맞아도 거부한다.
        guard header.entryType == .regularFile else { throw BackupArchiveError.rejected(path) }
        let size = dataSize ?? 0
        guard fileCount < maxEntryCount, size <= maxEntryBytes, size <= maxTotalBytes - totalBytes else {
            throw BackupArchiveError.tooLarge
        }
        fileCount += 1
        totalBytes += size
        if case .blob = entry {
            try makeDirectory(root.appendingPathComponent(BackupArchiveEntry.blobDirectoryPath, isDirectory: true))
        }
        try writeFile(at: root.appendingPathComponent(entry.path, isDirectory: false), size: size, from: decoder)
    }

    /// PAT 필드 원문
    private static func pathField(of header: ArchiveHeader) -> String? {
        guard case .string(_, let value)? = header.field(forKey: BackupArchiveField.path) else { return nil }
        return value
    }

    /// DAT 필드의 바이트 수. DAT 밖의 바이트 필드(확장 속성 · ACL 등)나 DAT 가 둘 이상이면 거부한다 — 읽지 않은 바이트를 남기지 않는다.
    private static func dataSize(of header: ArchiveHeader, path: String) throws -> UInt64? {
        var size: UInt64?
        for field in header {
            guard case .blob(let key, let blobSize, _) = field else { continue }
            guard key == BackupArchiveField.data, size == nil else { throw BackupArchiveError.rejected(path) }
            size = blobSize
        }
        return size
    }

    /// 루트 안에 폴더를 만든다(이미 있으면 그대로).
    private func makeDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw BackupArchiveError.ioFailed
        }
    }

    /// 새 파일을 만들고 바이트를 조각으로 옮겨 쓴다. 이미 있는 이름 · 링크에는 쓰지 않는다.
    private func writeFile(at url: URL, size: UInt64, from decoder: ArchiveStream) throws {
        let descriptor: FileDescriptor
        do {
            descriptor = try FileDescriptor.open(
                FilePath(url.path),
                .writeOnly,
                options: [.create, .exclusiveCreate, .noFollow],
                permissions: .ownerReadWrite
            )
        } catch {
            throw BackupArchiveError.ioFailed
        }
        try descriptor.closeAfter {
            var buffer = [UInt8](repeating: 0, count: Int(min(UInt64(BackupArchive.chunkBytes), max(size, 1))))
            var remaining = size
            while remaining > 0 {
                try Task.checkCancellation()
                let count = Int(min(UInt64(buffer.count), remaining))
                do {
                    try buffer.withUnsafeMutableBytes { raw in
                        try decoder.readBlob(key: BackupArchiveField.data, into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<count]))
                    }
                } catch {
                    throw BackupArchiveError.wrongPasswordOrDamaged
                }
                do {
                    try descriptor.writeAll(buffer[0..<count])
                } catch let code as Errno where code == .noSpace {
                    throw BackupArchiveError.insufficientSpace
                } catch {
                    throw BackupArchiveError.ioFailed
                }
                remaining -= UInt64(count)
            }
        }
    }
}
