//
//  BackupArchiveFileSink.swift
//  Domain
//
//  암호화 스트림이 쓰는 파일 끝 — 쓰기 실패를 AppleArchive 에 돌려주지 않고 기록만 한다.
//
//  iOS 17 의 AppleArchive Swift 래퍼는 close() 가 실패하면 해제(deinit) 때 같은 스트림을 다시 닫아 프로세스가 죽는다
//  (iPadOS 17.5 시뮬레이터에서 AAByteStreamClose SIGBUS 로 확인 — 26.2 는 괜찮다). 공간 부족 같은 파일 쓰기 실패가 암호화 스트림의
//  close() 실패로 번지지 않도록, 여기서는 늘 성공을 돌려주고 첫 실패(errno)를 남긴다. 쓰는 쪽은 다 닫은 뒤 `failure` 를 보고 실패로 끝낸다.
//

import AppleArchive
import Dependencies
import Foundation
import System

/// 파일 하나에 쓰는 사용자 정의 바이트 스트림. AEA 는 위치를 정해 쓴다(pwrite).
final class BackupArchiveFileSink: ArchiveByteStreamProtocol {
    /// 쓸 파일(읽기 · 쓰기로 연 것 — 닫기는 만든 쪽이 한다)
    private let descriptor: FileDescriptor
    /// 첫 쓰기 실패 — AppleArchive 가 작업 스레드에서 부를 수 있어 잠금으로 지킨다
    private let firstFailure = LockIsolated<Errno?>(nil)

    init(descriptor: FileDescriptor) {
        self.descriptor = descriptor
    }

    /// 첫 쓰기 실패(없으면 nil)
    var failure: Errno? { firstFailure.value }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try descriptor.read(into: buffer)
    }

    func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int {
        try descriptor.read(fromAbsoluteOffset: offset, into: buffer)
    }

    /// 이어 쓰기 — 실패하면 기록만 하고, 이미 실패했으면 쓰지 않는다. 늘 다 쓴 것으로 돌려준다.
    func write(from buffer: UnsafeRawBufferPointer) throws -> Int {
        record { try descriptor.writeAll(buffer) }
        return buffer.count
    }

    /// 위치를 정해 쓰기 — 실패 처리는 `write(from:)` 와 같다.
    func write(from buffer: UnsafeRawBufferPointer, atOffset offset: Int64) throws -> Int {
        record { _ = try descriptor.writeAll(toAbsoluteOffset: offset, buffer) }
        return buffer.count
    }

    func seek(toOffset offset: Int64, relativeTo origin: FileDescriptor.SeekOrigin) throws -> Int64 {
        try descriptor.seek(offset: offset, from: origin)
    }

    func cancel() {}

    /// 파일은 만든 쪽이 닫는다 — 여기서는 실패할 일이 없게 아무것도 하지 않는다.
    func close() throws {}

    /// 아직 실패가 없을 때만 쓰고, 실패하면 첫 errno 를 남긴다.
    private func record(_ operation: () throws -> Void) {
        guard firstFailure.value == nil else { return }
        do {
            try operation()
        } catch {
            let code = (error as? Errno) ?? .ioError
            firstFailure.withValue { $0 = $0 ?? code }
        }
    }
}
