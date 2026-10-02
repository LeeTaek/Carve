//
//  BackupFormatValidatorTesting.swift
//  DomainTest
//
//  필사 백업 형식 — 풀린 백업의 디코딩 · 검증(설계 §4-2). 어긋나면 저장소를 바꾸기 전에 파일 전체를 거부한다.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 형식 — 검증")
struct BackupFormatValidatorTesting {

    /// 표본 항목 · blob 을 폴더에 쓰고 검사한다. `mutate` 로 manifest 만 바꿀 수 있다.
    private func validate(
        items: [BackupItem] = BackupFormatSample.items(),
        blobs: [Data] = BackupFormatSample.blobs(),
        limits: BackupLimits = .default,
        mutate: (inout BackupManifest) -> Void = { _ in }
    ) throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeBlobs(blobs)
        var manifest = BackupFormatSample.manifest(items: items, blobs: blobs)
        mutate(&manifest)
        try BackupPayloadValidator.validate(manifest: manifest, items: items, blobDirectory: fixture.blobDirectory, limits: limits)
    }

    // MARK: - 통과

    @Test("표본 백업을 읽어 그대로 돌려준다")
    func loadsTheSample() throws {
        // Given
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeSample()

        // When
        let payload = try BackupPayload.load(rootDirectory: fixture.root, limits: .default)

        // Then
        let items = BackupFormatSample.items()
        #expect(payload.items == items)
        #expect(payload.manifest == BackupFormatSample.manifest(items: items, blobs: BackupFormatSample.blobs()))
        #expect(payload.manifest.counts == BackupCounts(rows: 4, drafts: 1, blobs: 5))
        #expect(payload.blobDirectory.lastPathComponent == "blobs")
        // 비운 행과 보관 행은 같은 메타데이터 blob 하나를 함께 가리킨다.
        #expect(items[1].metadataBlob == items[2].metadataBlob)
        #expect(try payload.blob(named: BackupFormat.sha256Hex(BackupFormatSample.inkVerse1)) == BackupFormatSample.inkVerse1)
    }

    @Test("항목도 blob 도 없는 백업은 blobs 폴더가 없어도 통과한다")
    func emptyBackupPasses() throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.write(manifest: BackupFormatSample.manifest(items: [], blobs: []), items: [])

        let payload = try BackupPayload.load(rootDirectory: fixture.root, limits: .default)

        #expect(payload.items.isEmpty)
    }

    // MARK: - 디코딩

    @Test("formatVersion 2 는 load 에서 unsupportedFormat")
    func loadRejectsFormatVersionTwo() throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeSample()
        try fixture.writeFile(Data(#"{"formatVersion":2}"#.utf8), name: BackupFormat.manifestFileName)

        #expect(throws: BackupFormatError.unsupportedFormat(formatVersion: 2)) {
            try BackupPayload.load(rootDirectory: fixture.root, limits: .default)
        }
        // 값으로 만든 manifest 도 같다.
        #expect(throws: BackupFormatError.unsupportedFormat(formatVersion: 2)) {
            try validate { $0.formatVersion = 2 }
        }
    }

    @Test("manifest 가 없거나 items 가 깨졌으면 malformed")
    func missingOrBrokenFilesAreMalformed() throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }

        #expect(throws: BackupFormatError.malformed(fileName: "manifest.json")) {
            try BackupPayload.load(rootDirectory: fixture.root, limits: .default)
        }

        try fixture.writeSample()
        try fixture.writeFile(Data("[{\"id\":".utf8), name: BackupFormat.itemsFileName)
        #expect(throws: BackupFormatError.malformed(fileName: "items.json")) {
            try BackupPayload.load(rootDirectory: fixture.root, limits: .default)
        }
    }

    // MARK: - 상한

    @Test("항목 수 상한")
    func itemLimit() {
        #expect(throws: BackupFormatError.limitExceeded(.items)) {
            try validate(limits: BackupLimits(maxItems: BackupFormatSample.items().count - 1))
        }
    }

    @Test("blob 하나 상한 — manifest 크기, 그리고 manifest 를 속인 실제 파일 크기")
    func blobByteLimit() throws {
        let largest = BackupFormatSample.blobs().map(\.count).max() ?? 0
        #expect(throws: BackupFormatError.limitExceeded(.blobBytes)) {
            try validate(limits: BackupLimits(maxBlobBytes: largest - 1))
        }

        // manifest 는 상한 안이라고 적었는데 실제 파일이 상한을 넘는다 — 상한 + 1 바이트까지만 읽고 거부한다.
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        let items = BackupFormatSample.items()
        let blobs = BackupFormatSample.blobs()
        try fixture.writeBlobs(blobs)
        let name = BackupFormat.sha256Hex(BackupFormatSample.inkVerse1)
        try fixture.writeBlob(Data(repeating: 7, count: largest + 10), name: name)
        #expect(throws: BackupFormatError.limitExceeded(.blobBytes)) {
            try BackupPayloadValidator.validate(
                manifest: BackupFormatSample.manifest(items: items, blobs: blobs),
                items: items,
                blobDirectory: fixture.blobDirectory,
                limits: BackupLimits(maxBlobBytes: largest)
            )
        }
    }

    @Test("풀린 합계 상한")
    func totalByteLimit() {
        let total = BackupFormatSample.blobs().map(\.count).reduce(0, +)
        #expect(throws: BackupFormatError.limitExceeded(.totalBytes)) {
            try validate(limits: BackupLimits(maxTotalBytes: total - 1))
        }
    }

    @Test("색인 파일(manifest.json · items.json)이 maxIndexBytes 를 넘으면 디코딩 전에 거부")
    func indexFileLimit() throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        try fixture.writeSample()
        let manifestSize = try Data(contentsOf: fixture.root.appendingPathComponent(BackupFormat.manifestFileName)).count
        let itemsSize = try Data(contentsOf: fixture.root.appendingPathComponent(BackupFormat.itemsFileName)).count
        #expect(itemsSize > manifestSize)

        // items.json 만 상한을 넘는다.
        #expect(throws: BackupFormatError.limitExceeded(.indexBytes)) {
            try BackupPayload.load(rootDirectory: fixture.root, limits: BackupLimits(maxIndexBytes: itemsSize - 1))
        }
        // manifest.json 도 넘는다 — 먼저 읽는 manifest 에서 멈춘다.
        #expect(throws: BackupFormatError.limitExceeded(.indexBytes)) {
            try BackupPayload.load(rootDirectory: fixture.root, limits: BackupLimits(maxIndexBytes: manifestSize - 1))
        }
        // 딱 맞으면 통과한다.
        let payload = try BackupPayload.load(rootDirectory: fixture.root, limits: BackupLimits(maxIndexBytes: itemsSize))
        #expect(payload.items.count == BackupFormatSample.items().count)
    }

    @Test("컨테이너 항목 상한은 blob 과 색인 파일 상한 중 큰 쪽")
    func archiveEntryLimitIsTheLargerOfBlobAndIndex() {
        #expect(BackupLimits.default.maxBlobBytes == 64 * 1024 * 1024)
        #expect(BackupLimits.default.maxIndexBytes == 128 * 1024 * 1024)
        #expect(BackupLimits.default.archiveEntryLimit == 128 * 1024 * 1024)
        #expect(BackupLimits(maxBlobBytes: 300, maxIndexBytes: 200).archiveEntryLimit == 300)
    }

    // MARK: - manifest

    @Test("counts 가 실제와 다르면 거부")
    func countsMismatch() {
        #expect(throws: BackupFormatError.countsMismatch) {
            try validate { $0.counts.rows += 1 }
        }
        #expect(throws: BackupFormatError.countsMismatch) {
            try validate { $0.counts = BackupCounts(rows: $0.counts.rows, drafts: $0.counts.drafts, blobs: $0.counts.blobs - 1) }
        }
    }

    @Test("blob 이름은 64자 소문자 hex 이고 sha256 과 같아야 한다")
    func blobNamesMustBeLowercaseSHA256Hex() {
        let name = BackupFormat.sha256Hex(BackupFormatSample.inkVerse1)
        let invalidNames = [name.uppercased(), String(name.dropLast()), "../" + String(name.dropFirst(3)), "manifest.json"]
        for invalid in invalidNames {
            #expect(throws: BackupFormatError.invalidBlobEntry(name: invalid)) {
                try validate { manifest in
                    manifest.blobs = manifest.blobs.map { $0.name == name ? BackupBlobEntry(name: invalid, size: $0.size, sha256: invalid) : $0 }
                }
            }
        }
        // 이름과 sha256 이 다르다.
        #expect(throws: BackupFormatError.invalidBlobEntry(name: name)) {
            try validate { manifest in
                manifest.blobs = manifest.blobs.map { $0.name == name ? BackupBlobEntry(name: name, size: $0.size, sha256: String(repeating: "0", count: 64)) : $0 }
            }
        }
        #expect(BackupFormat.isBlobName(name))
        #expect(!BackupFormat.isBlobName(String(repeating: "g", count: 64)))
    }

    @Test("manifest 에 같은 blob 이 두 번이면 거부")
    func duplicateBlobEntry() {
        #expect(throws: BackupFormatError.duplicateBlob(name: BackupFormat.sha256Hex(BackupFormatSample.inkVerse1))) {
            try validate { manifest in
                manifest.blobs.append(BackupBlobEntry(bytes: BackupFormatSample.inkVerse1))
                manifest.counts.blobs += 1
            }
        }
    }

    @Test("항목이 manifest 에 없는 blob 을 가리키면 거부")
    func itemReferencesBlobMissingFromManifest() {
        let name = BackupFormat.sha256Hex(BackupFormatSample.inkVerse3)
        #expect(throws: BackupFormatError.missingBlob(name: name)) {
            try validate { manifest in
                manifest.blobs.removeAll { $0.name == name }
                manifest.counts.blobs -= 1
            }
        }
    }

    @Test("manifest 의 blob 파일이 없으면 거부")
    func blobFileMissing() {
        var blobs = BackupFormatSample.blobs()
        blobs.removeAll { $0 == BackupFormatSample.inkDraft }
        #expect(throws: BackupFormatError.missingBlob(name: BackupFormat.sha256Hex(BackupFormatSample.inkDraft))) {
            let fixture = try BackupFormatFixture()
            defer { fixture.remove() }
            try fixture.writeBlobs(blobs)
            let items = BackupFormatSample.items()
            try BackupPayloadValidator.validate(
                manifest: BackupFormatSample.manifest(items: items, blobs: BackupFormatSample.blobs()),
                items: items,
                blobDirectory: fixture.blobDirectory,
                limits: .default
            )
        }
    }

    @Test("어느 항목도 가리키지 않는 blob 은 거부")
    func unreferencedBlob() {
        let stray = Data("stray".utf8)
        #expect(throws: BackupFormatError.unreferencedBlob(name: BackupFormat.sha256Hex(stray))) {
            try validate(blobs: BackupFormatSample.blobs() + [stray])
        }
    }

    // MARK: - blob 바이트

    @Test("blob 실제 크기가 다르면 거부")
    func blobSizeMismatch() throws {
        let name = BackupFormat.sha256Hex(BackupFormatSample.inkVerse1)
        #expect(throws: BackupFormatError.blobSizeMismatch(name: name)) {
            try validateWithTamperedBlob(name: name, bytes: BackupFormatSample.inkVerse1 + Data("+".utf8))
        }
    }

    @Test("blob 바이트가 바뀌면(같은 크기) 해시로 거부")
    func blobHashMismatch() throws {
        let name = BackupFormat.sha256Hex(BackupFormatSample.inkVerse1)
        var tampered = BackupFormatSample.inkVerse1
        tampered[tampered.startIndex] ^= 0x01
        #expect(throws: BackupFormatError.blobHashMismatch(name: name)) {
            try validateWithTamperedBlob(name: name, bytes: tampered)
        }
    }

    private func validateWithTamperedBlob(name: String, bytes: Data) throws {
        let fixture = try BackupFormatFixture()
        defer { fixture.remove() }
        let items = BackupFormatSample.items()
        let blobs = BackupFormatSample.blobs()
        try fixture.writeBlobs(blobs)
        try fixture.writeBlob(bytes, name: name)
        try BackupPayloadValidator.validate(
            manifest: BackupFormatSample.manifest(items: items, blobs: blobs),
            items: items,
            blobDirectory: fixture.blobDirectory,
            limits: .default
        )
    }

    // MARK: - 항목

    @Test("같은 id · 같은 내용 항목이 둘이면 중복 id")
    func duplicateItemID() {
        var items = BackupFormatSample.items()
        items.append(items[0])
        #expect(throws: BackupFormatError.duplicateItemID(items[0].id)) {
            try validate(items: items)
        }
    }

    @Test("같은 id 인데 지문이 다르면 무결성 오류")
    func sameIDDifferentFingerprint() {
        var items = BackupFormatSample.items()
        var impostor = items[3]
        impostor.id = items[0].id
        items.append(impostor)
        #expect(throws: BackupFormatError.integrity(itemID: items[0].id, .conflictingFingerprint)) {
            try validate(items: items)
        }
    }

    @Test("blob 으로 다시 계산한 지문이 항목 지문과 다르면 무결성 오류")
    func recomputedFingerprintMustMatch() {
        // 지문을 바꿨다.
        var forged = BackupFormatSample.items()
        forged[0].fingerprint = VerseContentFingerprint.make(lineData: Data("다른 잉크".utf8), drawingVersion: 3, layoutMetadataBlob: nil)
        #expect(throws: BackupFormatError.integrity(itemID: forged[0].id, .fingerprintMismatch)) {
            try validate(items: forged)
        }

        // 좌표 형식만 바꿨다 — 지문 입력이라 다시 계산하면 다르다.
        var relabeled = BackupFormatSample.items()
        relabeled[0].drawingVersion = 2
        #expect(throws: BackupFormatError.integrity(itemID: relabeled[0].id, .fingerprintMismatch)) {
            try validate(items: relabeled)
        }

        // 잉크가 없는 항목은 지문이 없어야 한다.
        var clearedWithFingerprint = BackupFormatSample.items()
        clearedWithFingerprint[1].fingerprint = clearedWithFingerprint[0].fingerprint
        #expect(throws: BackupFormatError.integrity(itemID: clearedWithFingerprint[1].id, .fingerprintMismatch)) {
            try validate(items: clearedWithFingerprint)
        }

        // 잉크가 있는데 지문이 빠졌다.
        var missingFingerprint = BackupFormatSample.items()
        missingFingerprint[3].fingerprint = nil
        #expect(throws: BackupFormatError.integrity(itemID: missingFingerprint[3].id, .fingerprintMismatch)) {
            try validate(items: missingFingerprint)
        }
    }
}
