//
//  BackupArchiveWriteFailureTesting.swift
//  DomainTest
//
//  쓰기 도중 실패 — 파일 쓰기 실패(공간 부족 등)와 항목을 다 쓰지 못한 중단이 오류로 끝나고 프로세스가 죽지 않는다.
//  iOS 17 의 AppleArchive Swift 래퍼는 실패한 close() 뒤 해제 때 같은 스트림을 다시 닫아 죽으므로(17.5 확인), 이 경로를 17.5 에서도 돌린다.
//

import Foundation
import System
import Testing

@testable import Domain

@Suite("백업 컨테이너 쓰기 실패")
struct BackupArchiveWriteFailureTesting {

    @Test("파일 쓰기가 실패하면 스트림은 정상으로 닫히고 첫 errno 로 끝난다")
    func sinkFailureSurfacesAfterClosing() throws {
        try BackupArchiveSandbox.run { sandbox in
            try sandbox.stageBackup(blobs: [BackupArchiveFixture.bytes(count: 300_000, seed: 71)])
            let entries = try BackupArchiveStagedEntry.list(in: sandbox.staged)
            try Data().write(to: sandbox.archive)
            // 읽기 전용으로 연 파일 — 모든 쓰기가 EBADF 로 실패한다
            let descriptor = try FileDescriptor.open(FilePath(sandbox.archive.path), .readOnly)
            defer { try? descriptor.close() }

            #expect(throws: Errno.badFileDescriptor) {
                try BackupArchive.encrypt(entries, into: descriptor, password: BackupArchiveFixture.password)
            }
        }
    }

    @Test("싱크는 실패를 AppleArchive 에 돌려주지 않고 첫 실패만 남긴다")
    func sinkRecordsFirstFailureOnly() throws {
        try BackupArchiveSandbox.run { sandbox in
            try Data().write(to: sandbox.archive)
            let descriptor = try FileDescriptor.open(FilePath(sandbox.archive.path), .readOnly)
            defer { try? descriptor.close() }
            let sink = BackupArchiveFileSink(descriptor: descriptor)
            let bytes: [UInt8] = [1, 2, 3]

            let written = try bytes.withUnsafeBytes { try sink.write(from: $0) }
            let positioned = try bytes.withUnsafeBytes { try sink.write(from: $0, atOffset: 10) }

            #expect(written == 3)
            #expect(positioned == 3)
            #expect(sink.failure == .badFileDescriptor)
        }
    }

    /// 항목 헤더를 쓴 뒤 바이트를 다 채우지 못하고 멈춘 경우 — 닫지 않고 해제한다.
    @Test("확인 뒤 줄어든 파일은 ioFailed 로 멈추고 죽지 않는다")
    func shrunkenFileAbortsMidEntry() throws {
        try BackupArchiveSandbox.run { sandbox in
            let blob = BackupArchiveFixture.bytes(count: 3 * BackupArchive.chunkBytes, seed: 81)
            try sandbox.stageBackup(blobs: [blob])
            let entries = try BackupArchiveStagedEntry.list(in: sandbox.staged)
            try blob.prefix(BackupArchive.chunkBytes + 10).write(to: sandbox.staged.appendingPathComponent("blobs/\(BackupArchiveFixture.blobName(blob))"))
            let descriptor = try FileDescriptor.open(
                FilePath(sandbox.archive.path), .readWrite, options: [.create, .truncate], permissions: .ownerReadWrite
            )
            defer { try? descriptor.close() }

            #expect(throws: BackupArchiveError.ioFailed) {
                try BackupArchive.encrypt(entries, into: descriptor, password: BackupArchiveFixture.password)
            }
        }
    }

    @Test("쓰기 · 풀기 실패는 공간 부족과 그 밖의 입출력으로 나뉜다")
    func failureMapping() {
        #expect(BackupArchive.failure(Errno.noSpace) as? BackupArchiveError == .insufficientSpace)
        #expect(BackupArchive.failure(Errno.ioError) as? BackupArchiveError == .ioFailed)
        #expect(BackupArchive.failure(Errno.badFileDescriptor) as? BackupArchiveError == .ioFailed)
        #expect(BackupArchive.failure(BackupArchiveError.entryRejected(name: "x")) as? BackupArchiveError == .entryRejected(name: "x"))
        #expect(BackupArchive.failure(CancellationError()) is CancellationError)
    }
}
