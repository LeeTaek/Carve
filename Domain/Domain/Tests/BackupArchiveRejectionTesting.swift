//
//  BackupArchiveRejectionTesting.swift
//  DomainTest
//
//  허용 밖 항목 · 상한 초과 · 공간 부족 · 취소 — 풀기는 그 자리에서 멈추고 루트를 지우며, 쓰기는 파일을 남기지 않는다(설계 §2-1 · §2-8 · §4-2).
//

import AppleArchive
import Foundation
import Testing

@testable import Domain

@Suite("백업 컨테이너 거부 · 상한")
struct BackupArchiveRejectionTesting {

    private typealias RawEntry = BackupArchiveFixture.RawEntry

    private static let validBlobName = String(repeating: "ab", count: 32)

    /// 허용 항목 둘(manifest · items)
    private var allowedEntries: [RawEntry] {
        [
            RawEntry(path: BackupArchiveEntry.manifestPath, data: BackupArchiveFixture.manifest),
            RawEntry(path: BackupArchiveEntry.itemsPath, data: BackupArchiveFixture.items)
        ]
    }

    /// 풀기를 시도하고 오류를 돌려준다. 풀 곳에는 아무것도 남지 않아야 하고, 샌드박스 밖으로 새어 나간 것도 없어야 한다.
    private func readFailure(
        _ sandbox: BackupArchiveSandbox,
        maxEntryBytes: Int = 64 << 20,
        maxTotalBytes: Int = 4 << 30,
        maxEntryCount: Int = .max,
        availableCapacity: (URL) -> Int64? = { _ in nil }
    ) -> Error? {
        defer {
            #expect(sandbox.listing(of: sandbox.work).isEmpty)
            #expect(sandbox.listing(of: sandbox.root).allSatisfy { !$0.contains("escape") })
        }
        do {
            _ = try BackupArchive.read(
                from: sandbox.archive,
                password: BackupArchiveFixture.password,
                into: sandbox.work,
                maxEntryBytes: maxEntryBytes,
                maxTotalBytes: maxTotalBytes,
                maxEntryCount: maxEntryCount,
                availableCapacity: availableCapacity
            )
            return nil
        } catch {
            return error
        }
    }

    // MARK: - 풀기: 이름 · 종류

    /// 이름 화이트리스트 — 다른 파일 · 빈 이름 · 대소문자 · 길이가 다른 blob · 폴더 아래 폴더.
    @Test(
        "허용 밖 이름은 entryRejected(name) 로 멈추고 아무것도 남기지 않는다",
        arguments: [
            "other.txt",
            "",
            "Manifest.json",
            "blobs/" + String(repeating: "AB", count: 32),
            "blobs/" + String(repeating: "ab", count: 31),
            "blobs/" + String(repeating: "ab", count: 33),
            "blobs/" + String(repeating: "ab", count: 32) + "/x",
            "blobs/escape"
        ]
    )
    func disallowedNameIsRejected(name: String) throws {
        try BackupArchiveSandbox.run { sandbox in
            try BackupArchiveFixture.writeRaw(allowedEntries + [RawEntry(path: name, data: Data("x".utf8))], to: sandbox.archive)

            let error = readFailure(sandbox)

            #expect(error as? BackupArchiveError == .entryRejected(name: name))
        }
    }

    /// 경로 이탈 · 절대 경로 · 정규형이 아닌 경로. AppleArchive 해독기가 헤더에서 먼저 거부하면(Xcode 27 SDK 확인) 손상으로,
    /// 해독기가 넘기면 이름 규칙이 거부한다 — 어느 쪽이든 풀 곳 밖은 물론 안에도 아무것도 쓰지 않는다.
    @Test(
        "경로 이탈 · 절대 경로는 풀지 않고 멈춘다",
        arguments: [
            "../escape.json",
            "blobs/../../escape.json",
            "/tmp/escape.json",
            "./manifest.json",
            "manifest.json/",
            "blobs//" + String(repeating: "ab", count: 32)
        ]
    )
    func escapingPathIsRejected(name: String) throws {
        try BackupArchiveSandbox.run { sandbox in
            try BackupArchiveFixture.writeRaw(allowedEntries + [RawEntry(path: name, data: Data("x".utf8))], to: sandbox.archive)

            let error = readFailure(sandbox)

            #expect([BackupArchiveError.entryRejected(name: name), .wrongPasswordOrDamaged].contains(error as? BackupArchiveError))
        }
    }

    @Test("링크 항목은 이름이 맞아도 거부한다")
    func linkEntryIsRejected() throws {
        try BackupArchiveSandbox.run { sandbox in
            let path = "blobs/\(Self.validBlobName)"
            try BackupArchiveFixture.writeRaw(
                allowedEntries + [RawEntry(path: path, type: .link, linkTarget: "../../escape")],
                to: sandbox.archive
            )

            let error = readFailure(sandbox)

            #expect(error as? BackupArchiveError == .entryRejected(name: path))
        }
    }

    @Test("파일 이름이 폴더로, 폴더 이름이 파일로 오면 거부한다", arguments: [
        ("manifest.json", ArchiveHeader.EntryType.directory.rawValue),
        ("blobs", ArchiveHeader.EntryType.regularFile.rawValue),
        ("items.json", ArchiveHeader.EntryType.fifo.rawValue)
    ])
    func mismatchedTypeIsRejected(path: String, typeRawValue: UInt32) throws {
        try BackupArchiveSandbox.run { sandbox in
            let type = ArchiveHeader.EntryType(rawValue: typeRawValue)
            let data: Data? = type == .regularFile ? Data("x".utf8) : nil
            try BackupArchiveFixture.writeRaw([RawEntry(path: path, type: type, data: data)], to: sandbox.archive)

            let error = readFailure(sandbox)

            #expect(error as? BackupArchiveError == .entryRejected(name: path))
        }
    }

    @Test("같은 이름이 두 번 오면 거부한다")
    func duplicateEntryIsRejected() throws {
        try BackupArchiveSandbox.run { sandbox in
            try BackupArchiveFixture.writeRaw(
                allowedEntries + [RawEntry(path: BackupArchiveEntry.manifestPath, data: Data("again".utf8))],
                to: sandbox.archive
            )

            let error = readFailure(sandbox)

            #expect(error as? BackupArchiveError == .entryRejected(name: BackupArchiveEntry.manifestPath))
        }
    }

    @Test("DAT 밖의 바이트 필드(확장 속성)가 붙은 항목은 거부한다")
    func extraBlobFieldIsRejected() throws {
        try BackupArchiveSandbox.run { sandbox in
            try BackupArchiveFixture.writeRaw(
                [RawEntry(path: BackupArchiveEntry.manifestPath, data: BackupArchiveFixture.manifest, extraBlob: Data("xattr".utf8))],
                to: sandbox.archive
            )

            let error = readFailure(sandbox)

            #expect(error as? BackupArchiveError == .entryRejected(name: BackupArchiveEntry.manifestPath))
        }
    }

    @Test("blobs 폴더 항목이 blob 뒤에 와도 풀린다")
    func blobDirectoryEntryMayFollowBlobs() throws {
        try BackupArchiveSandbox.run { sandbox in
            let blob = Data("ink".utf8)
            let path = "blobs/\(BackupArchiveFixture.blobName(blob))"
            try BackupArchiveFixture.writeRaw(
                allowedEntries + [RawEntry(path: path, data: blob), RawEntry(path: "blobs", type: .directory)],
                to: sandbox.archive
            )

            let root = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: 1 << 20, maxTotalBytes: 1 << 20
            )

            #expect(try sandbox.files(in: root)[path] == blob)
        }
    }

    // MARK: - 풀기: 상한 · 공간

    @Test("항목 하나가 상한을 넘으면 tooLarge — 같으면 풀린다")
    func entryLimitIsEnforced() throws {
        try BackupArchiveSandbox.run { sandbox in
            let blob = BackupArchiveFixture.bytes(count: 5_000, seed: 21)
            try BackupArchiveFixture.writeRaw(allowedEntries + [RawEntry(path: "blobs/\(BackupArchiveFixture.blobName(blob))", data: blob)], to: sandbox.archive)

            #expect(readFailure(sandbox, maxEntryBytes: blob.count - 1) as? BackupArchiveError == .tooLarge)
            let root = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: blob.count, maxTotalBytes: 1 << 20
            )
            #expect(try sandbox.files(in: root).count == 3)
        }
    }

    @Test("풀린 합계가 상한을 넘으면 tooLarge — 같으면 풀린다")
    func totalLimitIsEnforced() throws {
        try BackupArchiveSandbox.run { sandbox in
            let blobs = [BackupArchiveFixture.bytes(count: 3_000, seed: 31), BackupArchiveFixture.bytes(count: 4_000, seed: 32)]
            try BackupArchiveFixture.writeRaw(
                allowedEntries + blobs.map { RawEntry(path: "blobs/\(BackupArchiveFixture.blobName($0))", data: $0) },
                to: sandbox.archive
            )
            let total = BackupArchiveFixture.manifest.count + BackupArchiveFixture.items.count + 7_000

            #expect(readFailure(sandbox, maxTotalBytes: total - 1) as? BackupArchiveError == .tooLarge)
            let root = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: 1 << 20, maxTotalBytes: total
            )
            #expect(try sandbox.files(in: root).count == 4)
        }
    }

    /// 빈 blob 은 바이트 상한에 걸리지 않으므로 파일 수 상한이 따로 막는다(manifest · items · blob 을 모두 센다).
    @Test("풀 파일 수가 상한을 넘으면 tooLarge 로 멈추고 정리한다 — 같으면 풀린다")
    func entryCountLimitIsEnforced() throws {
        try BackupArchiveSandbox.run { sandbox in
            let emptyBlobs = (1...5).map { RawEntry(path: "blobs/" + String(format: "%064lx", $0), data: Data()) }
            try BackupArchiveFixture.writeRaw(allowedEntries + emptyBlobs, to: sandbox.archive)

            #expect(readFailure(sandbox, maxEntryCount: 6) as? BackupArchiveError == .tooLarge)
            let root = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: 1 << 20, maxTotalBytes: 1 << 20, maxEntryCount: 7
            )
            #expect(try sandbox.files(in: root).count == 7)
        }
    }

    @Test("풀 곳의 남은 공간이 풀린 크기보다 적으면 쓰기 전에 insufficientSpace")
    func readChecksSpaceFirst() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [BackupArchiveFixture.bytes(count: 50_000, seed: 41)])
            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)

            let error = readFailure(sandbox, availableCapacity: { _ in 10_000 })

            #expect(error as? BackupArchiveError == .insufficientSpace)
        }
    }

    // MARK: - 쓰기

    @Test("준비 폴더에 허용 밖 이름이 있으면 쓰지 않는다", arguments: [".DS_Store", "notes.txt", "blobs/not-a-hash", "blobs/" + String(repeating: "CD", count: 32)])
    func writeRejectsUnexpectedStagedFile(relativePath: String) throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [Data("ink".utf8)])
            try sandbox.stage(relativePath, Data("x".utf8))

            #expect(throws: BackupArchiveError.entryRejected(name: relativePath)) {
                try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
            }
            #expect(sandbox.listing(of: sandbox.output).isEmpty)
        }
    }

    @Test("준비 폴더의 링크 · 폴더가 된 blob 은 쓰지 않는다")
    func writeRejectsLinksAndNestedDirectories() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [])
            let linkPath = "blobs/\(Self.validBlobName)"
            try FileManager.default.createSymbolicLink(
                at: sandbox.staged.appendingPathComponent(linkPath),
                withDestinationURL: sandbox.root.appendingPathComponent("escape")
            )
            #expect(throws: BackupArchiveError.entryRejected(name: linkPath)) {
                try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
            }

            try FileManager.default.removeItem(at: sandbox.staged.appendingPathComponent(linkPath))
            try FileManager.default.createDirectory(at: sandbox.staged.appendingPathComponent(linkPath), withIntermediateDirectories: true)
            #expect(throws: BackupArchiveError.entryRejected(name: linkPath)) {
                try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
            }
            #expect(sandbox.listing(of: sandbox.output).isEmpty)
        }
    }

    @Test("남은 공간이 모자라면 쓰기 전에 insufficientSpace 이고 파일을 남기지 않는다")
    func writeChecksSpaceFirst() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [BackupArchiveFixture.bytes(count: 10_000, seed: 51)])

            #expect(throws: BackupArchiveError.insufficientSpace) {
                try BackupArchive.write(
                    stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password, availableCapacity: { _ in 1_000 }
                )
            }
            #expect(sandbox.listing(of: sandbox.output).isEmpty)
        }
    }

    @Test("쓸 폴더가 없으면 ioFailed 이고 아무것도 만들지 않는다")
    func writeToMissingFolderFails() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [Data("ink".utf8)])
            let missing = sandbox.root.appendingPathComponent("missing", isDirectory: true)

            #expect(throws: BackupArchiveError.ioFailed) {
                try BackupArchive.write(stagedDirectory: sandbox.staged, to: missing.appendingPathComponent("b.carvebackup"), password: BackupArchiveFixture.password)
            }
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    // MARK: - 취소

    @Test("취소된 작업의 쓰기 · 풀기는 CancellationError 로 멈추고 아무것도 남기지 않는다")
    func cancellationLeavesNothing() async throws {
        let sandbox = try BackupArchiveSandbox.make()
        defer { sandbox.remove() }
        try sandbox.stageBackup(blobs: [BackupArchiveFixture.bytes(count: 3 * BackupArchive.chunkBytes, seed: 61)])
        try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
        let staged = sandbox.staged
        let other = sandbox.output.appendingPathComponent("cancelled.carvebackup")
        let archive = sandbox.archive
        let work = sandbox.work

        // 작업이 스스로를 먼저 취소하고 부른다 — 시작 시점 경쟁 없이 취소된 상태를 만든다.
        let write = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try BackupArchive.write(stagedDirectory: staged, to: other, password: BackupArchiveFixture.password)
        }
        let read = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try BackupArchive.read(from: archive, password: BackupArchiveFixture.password, into: work, maxEntryBytes: 64 << 20, maxTotalBytes: 4 << 30)
        }

        await #expect(throws: CancellationError.self) { try await write.value }
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(sandbox.listing(of: sandbox.output) == ["backup.carvebackup"])
        #expect(sandbox.listing(of: sandbox.work).isEmpty)
    }
}
