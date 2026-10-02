//
//  BackupArchiveRoundTripTesting.swift
//  DomainTest
//
//  백업 컨테이너 왕복 — 준비 폴더를 암호화 파일로 쓰고 같은 암호로 풀면 이름 · 바이트가 같다(설계 §2-1 · §8-1 「컨테이너」).
//  iPadOS 17.5 에서도 돌려 scrypt 암호 프로필 동작을 확인한다.
//

import AppleArchive
import Foundation
import Testing

@testable import Domain

@Suite("백업 컨테이너 왕복")
struct BackupArchiveRoundTripTesting {

    private let entryLimit = 64 << 20
    private let totalLimit = 4 << 30

    @Test("준비 폴더를 쓰고 풀면 이름과 바이트가 그대로다")
    func roundTripKeepsNamesAndBytes() throws {
        try BackupArchiveSandbox.run { sandbox in
            // Given — 잉크 · 메타데이터 자리의 blob 셋(빈 blob 포함)
            let blobs = [Data("ink-v3".utf8), BackupArchiveFixture.bytes(count: 15_300, seed: 7), Data()]
            try sandbox.stageBackup(blobs: blobs)
            let staged = try sandbox.files(in: sandbox.staged)

            // When
            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
            let root = try BackupArchive.read(
                from: sandbox.archive,
                password: BackupArchiveFixture.password,
                into: sandbox.work,
                maxEntryBytes: entryLimit,
                maxTotalBytes: totalLimit
            )

            // Then — 풀린 루트는 풀 곳 안의 새 폴더이고, 허용 이름 밖의 것은 없다
            #expect(root.deletingLastPathComponent().standardizedFileURL == sandbox.work.standardizedFileURL)
            #expect(try sandbox.files(in: root) == staged)
            let expectedListing = (["blobs", "items.json", "manifest.json"] + blobs.map { "blobs/\(BackupArchiveFixture.blobName($0))" }).sorted()
            #expect(sandbox.listing(of: root) == expectedListing)
            // 원본 파일은 평문이 아니다 — 준비한 바이트가 그대로 보이지 않는다
            let archived = try Data(contentsOf: sandbox.archive)
            #expect(archived.range(of: Data("ink-v3".utf8)) == nil)
            #expect(archived.range(of: Data("manifest.json".utf8)) == nil)
        }
    }

    /// 조각(1 MiB)보다 큰 blob 은 쓰기 · 풀기 모두 여러 조각을 지난다.
    @Test("수 MB blob 도 조각으로 흘려 쓰고 풀어 바이트가 같다")
    func largeBlobStreamsThroughChunks() throws {
        try BackupArchiveSandbox.run { sandbox in
            let large = BackupArchiveFixture.bytes(count: 6 * BackupArchive.chunkBytes + 12_345, seed: 0x5EED)
            try sandbox.stageBackup(blobs: [large])

            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
            let root = try BackupArchive.read(
                from: sandbox.archive,
                password: BackupArchiveFixture.password,
                into: sandbox.work,
                maxEntryBytes: entryLimit,
                maxTotalBytes: totalLimit
            )

            let restored = try Data(contentsOf: root.appendingPathComponent("blobs/\(BackupArchiveFixture.blobName(large))"))
            #expect(restored == large)
        }
    }

    /// 화면 규칙(8자 이상)의 짧은 암호와 한글 암호도 쓰고 풀린다 — 암호 표기(`BackupArchivePassword`)가 SDK 길이 범위를 맞춘다.
    @Test("8자 암호 · 한글 암호로도 왕복한다", arguments: ["abcd1234", "새기다필사백업해요", "p@ss w0rd with a very long phrase that is still fine"])
    func passwordsOfAnyLengthRoundTrip(password: String) throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [Data("ink".utf8)])

            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: password)
            let root = try BackupArchive.read(
                from: sandbox.archive,
                password: password,
                into: sandbox.work,
                maxEntryBytes: entryLimit,
                maxTotalBytes: totalLimit
            )

            #expect(try sandbox.files(in: root) == (try sandbox.files(in: sandbox.staged)))
        }
    }

    /// SDK 의 암호 길이 범위(UTF-8 20~256 바이트)를 기록한다 — 이 범위 때문에 암호 표기가 있다. SDK 가 바뀌어 이 시험이 깨지면 표기를 다시 본다.
    @Test("SDK 는 20바이트보다 짧은 암호를 그대로는 받지 않는다")
    func sdkRejectsShortRawPassword() throws {
        let context = ArchiveEncryptionContext(profile: BackupArchive.profile, compressionAlgorithm: .lzfse)
        #expect(throws: (any Error).self) { try context.setPassword(BackupArchiveFixture.password) }
        #expect(throws: (any Error).self) { try context.setPassword(String(repeating: "a", count: 19)) }
        try context.setPassword(String(repeating: "a", count: 20))
        #expect(BackupArchivePassword.encoded(BackupArchiveFixture.password).utf8.count == 64)
        #expect(BackupArchivePassword.encoded(String(repeating: "가", count: 300)).utf8.count == 64)
    }

    /// 기대 값은 Swift 밖에서 따로 계산했다 — `printf '%s' 'carve.backupPassword/1|<NFC 암호>' | shasum -a 256`,
    /// Python `hashlib.sha256(("carve.backupPassword/1|" + unicodedata.normalize("NFC", 암호)).encode()).hexdigest()` 가 같은 값을 낸다.
    @Test(
        "암호 표기는 고정 값이고 조합형(NFD) 입력도 같은 값이다 — 바뀌면 이미 만든 백업을 열 수 없다",
        arguments: [
            ("abcd1234", "d5226a5e1eef97230a43b0316f770d0fec9c5e7b7898a07bf6667eebba4e7c8d"),
            ("가나다라마바사아", "3a8188949b7a58249959d3ff4d9b64cdddc16a6d0b9e3a08bd55fbdd8c02ceb6")
        ]
    )
    func passwordEncodingIsStable(password: String, expectedHex: String) {
        #expect(BackupArchivePassword.encoded(password.precomposedStringWithCanonicalMapping) == expectedHex)
        #expect(BackupArchivePassword.encoded(password.decomposedStringWithCanonicalMapping) == expectedHex)
    }

    /// 하드웨어 키보드 · 붙여넣기로 들어온 조합형(NFD) 한글 암호로 만든 파일을, 완성형(NFC)으로 친 같은 암호로 연다.
    @Test("조합형(NFD) 한글 암호로 만든 백업을 완성형(NFC) 암호로 연다")
    func decomposedKoreanPasswordOpensWithComposedPassword() throws {
        try BackupArchiveSandbox.run { sandbox in
            let composed = "가나다라마바사아".precomposedStringWithCanonicalMapping
            let decomposed = "가나다라마바사아".decomposedStringWithCanonicalMapping
            // 두 입력의 바이트가 실제로 다르다(String 의 == 는 정규 동치로 견주므로 UTF-8 로 본다)
            #expect(Array(composed.utf8) != Array(decomposed.utf8))
            try sandbox.stageBackup(blobs: [Data("ink".utf8)])

            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: decomposed)
            let root = try BackupArchive.read(
                from: sandbox.archive,
                password: composed,
                into: sandbox.work,
                maxEntryBytes: entryLimit,
                maxTotalBytes: totalLimit
            )

            #expect(try sandbox.files(in: root) == (try sandbox.files(in: sandbox.staged)))
        }
    }

    @Test("이미 있는 파일은 원자적으로 바뀌고 임시 파일이 남지 않는다")
    func writeReplacesDestinationWithoutLeftovers() throws {
        try BackupArchiveSandbox.run { sandbox in
            try Data("old file".utf8).write(to: sandbox.archive)
            try sandbox.stageBackup(blobs: [Data("new".utf8)])

            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)

            #expect(sandbox.listing(of: sandbox.output) == ["backup.carvebackup"])
            let root = try BackupArchive.read(
                from: sandbox.archive,
                password: BackupArchiveFixture.password,
                into: sandbox.work,
                maxEntryBytes: entryLimit,
                maxTotalBytes: totalLimit
            )
            #expect(try sandbox.files(in: root)["blobs/\(BackupArchiveFixture.blobName(Data("new".utf8)))"] == Data("new".utf8))
        }
    }

    @Test("같은 백업을 두 번 풀면 서로 다른 루트에 풀린다")
    func eachReadUsesFreshRoot() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [])
            try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)

            let first = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: entryLimit, maxTotalBytes: totalLimit
            )
            let second = try BackupArchive.read(
                from: sandbox.archive, password: BackupArchiveFixture.password, into: sandbox.work, maxEntryBytes: entryLimit, maxTotalBytes: totalLimit
            )

            #expect(first != second)
            #expect(try sandbox.files(in: first) == (try sandbox.files(in: second)))
        }
    }
}
