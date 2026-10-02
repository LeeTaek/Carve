//
//  BackupArchiveDamageTesting.swift
//  DomainTest
//
//  틀린 암호 · 변조 · 잘림은 하나의 오류(wrongPasswordOrDamaged)로 거부하고, 풀던 평문을 남기지 않는다(설계 §2-1 · §4-2).
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 컨테이너 손상 · 암호")
struct BackupArchiveDamageTesting {

    /// 여러 조각에 걸친 백업 파일을 만들고 그 바이트를 돌려준다.
    private func writeBackup(in sandbox: BackupArchiveSandbox) throws -> Data {
        try sandbox.stageBackup(blobs: [
            BackupArchiveFixture.bytes(count: 2 * BackupArchive.chunkBytes + 777, seed: 11),
            Data("small ink".utf8)
        ])
        try BackupArchive.write(stagedDirectory: sandbox.staged, to: sandbox.archive, password: BackupArchiveFixture.password)
        return try Data(contentsOf: sandbox.archive)
    }

    /// 풀기를 시도하고 오류를 돌려준다. 풀 곳에는 아무것도 남지 않아야 한다.
    private func readFailure(_ sandbox: BackupArchiveSandbox, from source: URL, password: String = BackupArchiveFixture.password) -> Error? {
        defer { #expect(sandbox.listing(of: sandbox.work).isEmpty) }
        do {
            _ = try BackupArchive.read(from: source, password: password, into: sandbox.work, maxEntryBytes: 64 << 20, maxTotalBytes: 4 << 30)
            return nil
        } catch {
            return error
        }
    }

    @Test("틀린 암호는 wrongPasswordOrDamaged 이고 풀린 것이 없다", arguments: ["abcd1235", "ABCD1234", "abcd1234 ", ""])
    func wrongPasswordIsRejected(password: String) throws {
        try BackupArchiveSandbox.run { sandbox in
            _ = try writeBackup(in: sandbox)

            let error = readFailure(sandbox, from: sandbox.archive, password: password)

            #expect(error as? BackupArchiveError == .wrongPasswordOrDamaged)
        }
    }

    /// 앞머리(문맥) · 첫 조각 · 가운데 · 끝 무결성 정보 — 어디를 바꿔도 같은 오류다.
    @Test("한 바이트만 바꿔도 wrongPasswordOrDamaged 이고 풀린 것이 없다", arguments: [0.0, 0.001, 0.02, 0.5, 0.97, 1.0])
    func singleByteTamperIsRejected(position: Double) throws {
        try BackupArchiveSandbox.run { sandbox in
            var bytes = try writeBackup(in: sandbox)
            let index = min(Int(Double(bytes.count) * position), bytes.count - 1)
            bytes[index] ^= 0x01
            let tampered = sandbox.output.appendingPathComponent("tampered.carvebackup")
            try bytes.write(to: tampered)

            let error = readFailure(sandbox, from: tampered)

            #expect(error as? BackupArchiveError == .wrongPasswordOrDamaged)
        }
    }

    /// 끝 한 바이트 · 조각 경계 근처 · 가운데 · 앞머리만 — 어디서 잘려도 풀린 것을 남기지 않는다.
    @Test("잘린 파일은 wrongPasswordOrDamaged 이고 풀린 것이 없다", arguments: [1, 64, 4_096, 65_536, 1 << 20, -1])
    func truncatedFileIsRejected(keptOrDropped: Int) throws {
        try BackupArchiveSandbox.run { sandbox in
            let bytes = try writeBackup(in: sandbox)
            // 음수는 끝에서 그만큼 버린다
            let kept = keptOrDropped < 0 ? bytes.count + keptOrDropped : keptOrDropped
            let truncated = sandbox.output.appendingPathComponent("truncated.carvebackup")
            try bytes.prefix(kept).write(to: truncated)

            let error = readFailure(sandbox, from: truncated)

            #expect(error as? BackupArchiveError == .wrongPasswordOrDamaged)
        }
    }

    @Test("백업 파일이 아니면 wrongPasswordOrDamaged 다", arguments: [0, 3, 4_096])
    func nonArchiveIsRejected(length: Int) throws {
        try BackupArchiveSandbox.run { sandbox in
            let other = sandbox.output.appendingPathComponent("other.carvebackup")
            try BackupArchiveFixture.bytes(count: length, seed: 3).write(to: other)

            let error = readFailure(sandbox, from: other)

            #expect(error as? BackupArchiveError == .wrongPasswordOrDamaged)
        }
    }

    @Test("없는 파일은 ioFailed 다")
    func missingFileIsIOFailure() throws {
        try BackupArchiveSandbox.run { sandbox in
            let error = readFailure(sandbox, from: sandbox.output.appendingPathComponent("missing.carvebackup"))

            #expect(error as? BackupArchiveError == .ioFailed)
        }
    }
}
