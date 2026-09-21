//
//  RecoveryCopyStoreTesting.swift
//  DomainTest
//
//  복구 사본 저장소 — 저장은 아무것도 지우지 않고, 삭제는 명시적일 때만 (정책 §12-6 C11).
//

import Foundation
import Testing

@testable import Domain

@Suite("복구 사본 저장소")
struct RecoveryCopyStoreTesting {

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID().uuidString)", isDirectory: true)
    }

    private func entry(
        fingerprint: String,
        classification: RecoveryCopyClassification = .preserved,
        account: String = "account-A",
        verse: String = "NKRV/1-01Genesis.txt/1/1"
    ) -> RecoveryCopyEntry {
        RecoveryCopyEntry(
            kind: .version,
            classification: classification,
            accountScope: account,
            verseKey: verse,
            contentFingerprint: fingerprint,
            drawingVersion: 3,
            knownEpochs: ["E1"],
            deviceID: "device-1"
        )
    }

    @Test("저장한 사본을 그대로 다시 읽는다")
    func savesAndReadsBack() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)
        let saved = entry(fingerprint: "vc1-aaa")

        try store.save(saved, blob: Data("획".utf8))

        let entries = try store.entries(accountScope: "account-A")
        #expect(entries == [saved])
        #expect(try store.blob(for: saved) == Data("획".utf8))
    }

    /// 저장이 자리를 만들려고 무언가를 지우면, 되살릴 사본이 조용히 사라진다.
    @Test("저장은 기존 사본을 지우지 않는다")
    func savingNeverEvicts() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)
        let first = entry(fingerprint: "vc1-aaa")
        let second = entry(fingerprint: "vc1-bbb", verse: "NKRV/1-01Genesis.txt/1/2")

        try store.save(first, blob: Data("첫 획".utf8))
        try store.save(second, blob: Data("둘째 획".utf8))
        try store.save(entry(fingerprint: "vc1-ccc", verse: "NKRV/1-01Genesis.txt/1/3"), blob: Data("셋째 획".utf8))

        let entries = try store.entries(accountScope: "account-A")
        #expect(entries.count == 3)
        #expect(try store.blob(for: first) == Data("첫 획".utf8))
        #expect(try store.blob(for: second) == Data("둘째 획".utf8))
    }

    @Test("같은 내용은 blob 하나를 공유하고 사용량도 한 번만 센다")
    func sharesBlobsByFingerprint() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)
        let blob = Data("같은 획".utf8)

        try store.save(entry(fingerprint: "vc1-same"), blob: blob)
        try store.save(entry(fingerprint: "vc1-same", classification: .quarantined), blob: blob)

        let usage = try store.usage(accountScope: "account-A")
        #expect(usage.preservedEntries == 1)
        #expect(usage.quarantinedEntries == 1)
        #expect(usage.blobBytes == blob.count)
    }

    @Test("삭제는 참조가 모두 사라졌을 때만 내용을 지운다")
    func removesBlobOnlyWhenUnreferenced() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)
        let keep = entry(fingerprint: "vc1-same")
        let drop = entry(fingerprint: "vc1-same", classification: .quarantined)
        try store.save(keep, blob: Data("같은 획".utf8))
        try store.save(drop, blob: Data("같은 획".utf8))

        try store.remove(entryID: drop.entryID, accountScope: "account-A")
        #expect(try store.entries(accountScope: "account-A") == [keep])
        // 남은 사본이 같은 내용을 참조하므로 blob 은 남는다.
        #expect(try store.blob(for: keep) == Data("같은 획".utf8))

        try store.remove(entryID: keep.entryID, accountScope: "account-A")
        #expect(try store.entries(accountScope: "account-A").isEmpty)
        #expect(throws: RecoveryCopyStoreError.blobMissing("vc1-same")) { try store.blob(for: keep) }
    }

    /// S13 — 다른 계정 범위의 사본을 새 계정 화면에 섞지 않는다.
    @Test("계정 범위가 다르면 목록에 섞이지 않는다")
    func keepsAccountScopesApart() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)

        try store.save(entry(fingerprint: "vc1-a", account: "account-A"), blob: Data("A".utf8))
        try store.save(entry(fingerprint: "vc1-b", account: "account-B"), blob: Data("B".utf8))

        #expect(try store.entries(accountScope: "account-A").map(\.contentFingerprint) == ["vc1-a"])
        #expect(try store.entries(accountScope: "account-B").map(\.contentFingerprint) == ["vc1-b"])
        #expect(try store.usage(accountScope: "account-B").preservedEntries == 1)
    }

    @Test("저장할 수 없으면 던진다 — 확정을 멈추기 위해서다")
    func failingSaveThrows() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("파일".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        // 일반 파일 아래에는 디렉터리를 만들 수 없다 — 쓰지 못하는 상황을 그대로 재현한다.
        let store = FileRecoveryCopyStore(root: blocker.appendingPathComponent("recovery", isDirectory: true))

        #expect(throws: (any Error).self) { try store.save(entry(fingerprint: "vc1-aaa"), blob: Data("획".utf8)) }
    }
}
