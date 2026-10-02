//
//  BackupWorkDirectory.swift
//  Domain
//
//  백업 · 불러오기의 평문 작업 폴더 — FileManager.temporaryDirectory/BackupWork/<UUID>/ 하나다(설계 §3 · §4-1 단계 10).
//  끝나면(성공 · 실패 · 취소) remove(), 앱 시작 때 removeStale() 로 지난 실행이 남긴 것을 지운다.
//

import CarveToolkit
import Foundation

/// 백업 작업 하나의 평문 폴더.
/// 앱을 다시 열어도 남겨야 하는 것(불러오기 작업 기록 · 암호화된 사본)은 여기에 두지 않는다 — `removeStale()` 이 `BackupWork` 를 통째로 지운다.
public struct BackupWorkDirectory: Hashable, Sendable {
    /// 이 작업의 폴더 — `BackupWork/<UUID>/`
    public let url: URL

    /// 모든 작업 폴더의 부모 — `FileManager.temporaryDirectory/BackupWork`
    public static var rootURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("BackupWork", isDirectory: true)
    }

    /// 새 작업 폴더를 만든다.
    /// - 출력: 비어 있는 새 폴더(소유자만 접근)
    /// - 부작용: 폴더 생성. 만들지 못하면 `BackupArchiveError.ioFailed`
    public static func make() throws -> BackupWorkDirectory {
        try make(under: rootURL)
    }

    /// `make()` 의 본체 — 시험이 부모 폴더를 바꾼다.
    static func make(under root: URL) throws -> BackupWorkDirectory {
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            Log.error("백업 작업 폴더를 만들지 못했다", "\(error)")
            throw BackupArchiveError.ioFailed
        }
        return BackupWorkDirectory(url: url)
    }

    /// 이 작업 폴더를 통째로 지운다. 이미 없으면 아무것도 하지 않는다.
    /// - 부작용: 파일 삭제. 지우지 못하면 로그만 남긴다 — 다음 앱 시작의 `removeStale()` 이 다시 지운다
    public func remove() {
        Self.removeItem(at: url)
    }

    /// 지난 실행이 남긴 작업 폴더를 모두 지운다 — 앱 시작 때 부른다(그때는 백업 작업이 없다).
    /// - 부작용: `BackupWork` 삭제. 지우지 못하면 로그만 남긴다
    public static func removeStale() {
        removeStale(under: rootURL)
    }

    /// `removeStale()` 의 본체 — 시험이 부모 폴더를 바꾼다.
    static func removeStale(under root: URL) {
        removeItem(at: root)
    }

    /// 항목을 지운다. 없으면 조용히 넘어가고, 그 밖의 실패는 로그로 남긴다(경로에는 UUID 만 있다).
    private static func removeItem(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            Log.error("백업 작업 폴더를 지우지 못했다", "\(error)")
        }
    }
}
