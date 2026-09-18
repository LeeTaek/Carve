//
//  DurableFile.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 전원이 꺼져도 남아야 하는 작은 기록(사본 목록 · 완료 표시)을 쓴다 (정책 §12-6 C3 · C11).
///
/// `Data.write(options: .atomic)` 은 임시 파일에 쓰고 이름을 바꿀 뿐 **저장 장치까지 내려 보내지 않는다.**
/// Apple 플랫폼의 `fsync` 는 드라이브 캐시를 비우지 않으므로 `F_FULLFSYNC` 로 내린 뒤 이름을 바꾼다.
/// 그래야 "기록이 있다" 가 "내용이 끝까지 있다" 를 뜻한다.
enum DurableFile {
    /// 임시 파일에 쓰고 장치까지 내린 뒤 제자리로 옮긴다. 기존 파일은 한 번에 바뀐다.
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            try flush(temporary)
            guard rename(temporary.path, url.path) == 0 else { throw posixError() }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        // 이름 바꾸기까지 내린다. 디렉터리에 `F_FULLFSYNC` 를 받지 않는 파일 시스템이 있어 실패는 무시한다.
        try? flush(directory)
    }

    /// 파일(또는 디렉터리)의 내용을 장치까지 내린다.
    static func flush(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 {
            throw posixError()
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
