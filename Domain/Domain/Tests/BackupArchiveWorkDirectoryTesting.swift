//
//  BackupArchiveWorkDirectoryTesting.swift
//  DomainTest
//
//  평문 작업 폴더(BackupWorkDirectory) — temporaryDirectory/BackupWork/<UUID>/ 하나를 만들고, 끝나면 지우고, 앱 시작 때 남은 것을 지운다.
//  실제 BackupWork 를 통째로 지우는 removeStale() 은 병렬 시험과 간섭하므로 부모 폴더를 바꿔 본다.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 작업 폴더")
struct BackupArchiveWorkDirectoryTesting {

    /// 이 시험만의 BackupWork 자리에서 `body` 를 돌리고 지운다.
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-work-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("BackupWork", isDirectory: true))
    }

    @Test("작업 폴더는 temporaryDirectory/BackupWork/<UUID> 이다")
    func liveWorkDirectoryLivesUnderTemporaryBackupWork() throws {
        let expectedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BackupWork", isDirectory: true)
        #expect(BackupWorkDirectory.rootURL.standardizedFileURL == expectedRoot.standardizedFileURL)

        let work = try BackupWorkDirectory.make()
        defer { work.remove() }

        #expect(work.url.deletingLastPathComponent().standardizedFileURL == expectedRoot.standardizedFileURL)
        #expect(UUID(uuidString: work.url.lastPathComponent) != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.url.path).isEmpty)
    }

    @Test("만들 때마다 새 빈 폴더이고 소유자만 접근한다")
    func makeCreatesFreshPrivateDirectories() throws {
        try withRoot { root in
            let first = try BackupWorkDirectory.make(under: root)
            let second = try BackupWorkDirectory.make(under: root)

            #expect(first != second)
            for work in [first, second] {
                let attributes = try FileManager.default.attributesOfItem(atPath: work.url.path)
                #expect(attributes[.type] as? FileAttributeType == .typeDirectory)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            }
        }
    }

    @Test("remove() 는 그 작업 폴더만 통째로 지우고, 다시 불러도 괜찮다")
    func removeDeletesOnlyThatDirectory() throws {
        try withRoot { root in
            let work = try BackupWorkDirectory.make(under: root)
            let other = try BackupWorkDirectory.make(under: root)
            try FileManager.default.createDirectory(at: work.url.appendingPathComponent("Unpacked/blobs"), withIntermediateDirectories: true)
            try Data("plain ink".utf8).write(to: work.url.appendingPathComponent("Unpacked/blobs/ink"))

            work.remove()
            work.remove()

            #expect(!FileManager.default.fileExists(atPath: work.url.path))
            #expect(FileManager.default.fileExists(atPath: other.url.path))
        }
    }

    @Test("removeStale() 은 지난 실행이 남긴 작업 폴더를 모두 지우고, 그 뒤에도 새로 만들 수 있다")
    func removeStaleDeletesEverything() throws {
        try withRoot { root in
            let left = [try BackupWorkDirectory.make(under: root), try BackupWorkDirectory.make(under: root)]
            try Data("plain".utf8).write(to: left[0].url.appendingPathComponent("items.json"))

            BackupWorkDirectory.removeStale(under: root)
            BackupWorkDirectory.removeStale(under: root)

            #expect(!FileManager.default.fileExists(atPath: root.path))
            let fresh = try BackupWorkDirectory.make(under: root)
            #expect(FileManager.default.fileExists(atPath: fresh.url.path))
        }
    }

    /// 실제 흐름 — 작업 폴더에 준비 · 풀기를 하고 끝나면 지운다.
    @Test("작업 폴더 안에서 쓰고 푼 평문은 remove() 로 남지 않는다")
    func plaintextIsGoneAfterRemove() throws {
        try withRoot { root in
            let work = try BackupWorkDirectory.make(under: root)
            let staged = work.url.appendingPathComponent("staged", isDirectory: true)
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            try BackupArchiveFixture.manifest.write(to: staged.appendingPathComponent(BackupArchiveEntry.manifestPath))
            let archive = root.appendingPathComponent("backup.carvebackup")
            try BackupArchive.write(stagedDirectory: staged, to: archive, password: BackupArchiveFixture.password)
            let unpacked = try BackupArchive.read(
                from: archive, password: BackupArchiveFixture.password, into: work.url, maxEntryBytes: 1 << 20, maxTotalBytes: 1 << 20
            )
            #expect(FileManager.default.fileExists(atPath: unpacked.appendingPathComponent(BackupArchiveEntry.manifestPath).path))

            work.remove()

            #expect(!FileManager.default.fileExists(atPath: work.url.path))
            #expect(FileManager.default.fileExists(atPath: archive.path))
        }
    }
}
